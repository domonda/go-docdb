// Provides test fixtures for the pgstore package

package pgfixtures

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"maps"
	"os"
	"reflect"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/storeconn/pgstore"
	"github.com/domonda/go-errs"
	"github.com/domonda/go-sqldb"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-sqldb/pqconn"
	"github.com/domonda/go-types/uu"
)

// globalConn lazily connects to the test Postgres database once per process.
// Connection and ping failures are returned rather than panicked so that
// FixtureGlobalConn can report them through *testing.T.
var globalConn = sync.OnceValues(func() (sqldb.Connection, error) {
	return connectFromEnv(context.Background())
})

// CloseGlobalConn closes the process-wide test database connection
// if one was successfully opened.
func CloseGlobalConn() {
	conn, err := globalConn()
	if err == nil {
		conn.Close() //#nosec G104
	}
}

// FixtureGlobalConn returns the process-wide test database connection.
// An unreachable database fails the test rather than skipping it: a test built
// on this fixture verifies nothing without a database, and a skip is reported
// as success by both the go test summary and its exit code, so skipping would
// let a run that exercised none of these tests pass. Start the database with
// run_tests.sh.
var FixtureGlobalConn = newFixture(func(t *testing.T) sqldb.Connection {
	conn, err := globalConn()
	if err != nil {
		t.Fatalf("Postgres test database not available, start it with run_tests.sh: %v", err)
	}
	return conn
})

var FixtureCtxWithTestTx = newFixture(func(t *testing.T) context.Context {
	tx, err := FixtureGlobalConn(t).Begin(t.Context(), sqldb.NextTransactionID(), nil)
	if err != nil {
		t.Fatalf("Failed to begin the transaction, %v", err)
		return nil
	}

	t.Cleanup(func() { tx.Rollback() }) //#nosec G104
	ctx := db.ContextWithConn(t.Context(), tx)
	return ctx
})

var FixturePopulator = newFixture(func(t *testing.T) *Populator {
	return &Populator{
		t:           t,
		ctx:         FixtureCtxWithTestTx(t),
		lastVersion: make(map[uu.ID]docdb.VersionTime),
	}
})

// Populator inserts fixture rows for one test. It is handed out per *testing.T
// by FixturePopulator, so the generated values below are counted per test
// rather than per process and belong to a single test goroutine.
type Populator struct {
	t   *testing.T
	ctx context.Context

	// mu guards the generated state below. A Populator belongs to one test and
	// is normally used from its goroutine alone, but nothing stops a test from
	// taking one at the parent level and using it from parallel subtests — the
	// process-wide atomic counter this replaced could not race that way, and a
	// plain counter plus a plain map can. run_tests.sh runs without -race, so
	// such a race would not be reported.
	mu sync.Mutex
	// seq numbers the file values generated for this test, see nextDocName.
	seq int64
	// versionSeq numbers the version timestamps generated for this test, see
	// NextVersion.
	versionSeq int64
	// lastVersion is the version of the row this fixture created last for a
	// document, which is what the next version of that document links to as its
	// predecessor.
	lastVersion map[uu.ID]docdb.VersionTime
}

func (populator *Populator) DocumentVersion(data ...map[string]any) *pgstore.DocumentVersion {
	merged := mergedData(data...)
	version, ok := merged["Version"].(docdb.VersionTime)
	if !ok {
		version = populator.NextVersion()
	}
	documentID := uu.IDv7()
	if id, ok := merged["DocumentID"].(uu.ID); ok {
		documentID = id
	}

	// Link the predecessor to the version this fixture inserted for the same
	// document before, so a multi-version document has a chain whose links name
	// versions that exist. Deriving it from this row's own version instead —
	// one second before it — names a version that was never inserted, because
	// a caller building a second version picks its timestamp independently of
	// the first: every test that walks the chain then reads a dangling
	// predecessor, and reads a different one on every run.
	//
	// A document's first version has nothing to link to, so the derived value
	// stands in. It only has to differ per document there, which is what keeps
	// the one-successor-per-version index from rejecting two genesis rows.
	prevVersion := populator.linkPrevVersion(documentID, version)

	return insertRecordWithExtraData(
		pgstore.DocumentVersion{
			ID:            uu.IDv7(),
			DocumentID:    documentID,
			CompanyID:     uu.IDv7(),
			Version:       version,
			PrevVersion:   new(prevVersion),
			CommitUserID:  uu.IDv7(),
			CommitReason:  "test",
			AddedFiles:    []string{populator.nextDocName(), populator.nextDocName()},
			ModifiedFiles: []string{populator.nextDocName(), populator.nextDocName()},
			RemovedFiles:  []string{populator.nextDocName(), populator.nextDocName()},
		}, populator, data...)
}

func (populator *Populator) DocumentVersionFile(data ...map[string]any) *pgstore.DocumentVersionFile {
	docVersion := createRecordIfNeeded("DocumentVersion", populator.DocumentVersion, data...)

	// Name, Size and Hash describe one imagined content, so overriding the hash
	// alone stores a file whose size contradicts it. Every read of such a file
	// through docdb.ReadHashedDocument then fails on the size mismatch instead
	// of on whatever the test is about, so overriding the content means
	// overriding both.
	merged := mergedData(data...)
	_, hashGiven := merged["Hash"]
	_, sizeGiven := merged["Size"]
	if hashGiven != sizeGiven {
		populator.t.Fatal("DocumentVersionFile: override Hash and Size together, so the stored size describes the content the hash was taken of")
	}

	name, size, hash := populator.nextDocFile()
	return insertRecordWithExtraData(
		pgstore.DocumentVersionFile{
			DocumentVersionID: docVersion.ID,
			Name:              name,
			Size:              size,
			Hash:              hash,
			DocumentVersion:   docVersion,
		}, populator, data...)
}

// mergedData combines the variadic override maps of the fixture constructors
// into the one map they all read, with a later map winning over an earlier one
// for a key both name.
//
// Every place that reads an override goes through this, so passing more than
// one map means the same thing everywhere. Reading only data[0] instead — which
// is what the constructors used to do, each on its own — silently dropped every
// later map: an override in one was neither applied nor rejected, and the
// fixture was inserted with the generated default the caller had asked to
// replace.
func mergedData(data ...map[string]any) map[string]any {
	switch len(data) {
	case 0:
		return nil
	case 1:
		return data[0]
	}
	merged := make(map[string]any)
	for _, d := range data {
		maps.Copy(merged, d)
	}
	return merged
}

func createRecordIfNeeded[T any](
	key string,
	createRecord func(data ...map[string]any) *T,
	data ...map[string]any,
) *T {
	if res, ok := mergedData(data...)[key]; ok {
		return res.(*T)
	}

	return createRecord(data...)
}

func insertRecordWithExtraData[T sqldb.StructWithTableName](
	baseRecord T,
	populator *Populator,
	data ...map[string]any,
) *T {
	record := fillDataIntoStruct(baseRecord, data...)

	err := db.InsertRowStruct(populator.ctx, *record)
	if err != nil {
		populator.t.Fatalf("Failed to insert record: %v", err)
	}

	return record
}

func fillDataIntoStruct[T any](obj T, data ...map[string]any) *T {
	ref := reflect.ValueOf(&obj).Elem()
	for key, value := range mergedData(data...) {
		field := ref.FieldByName(key)
		if !field.IsValid() {
			continue
		}
		newVal := reflect.ValueOf(value)
		field.Set(newVal)
	}
	return &obj
}

// fixtureVersionBase is the instant the generated version timestamps count
// from. Any fixed instant would do; this one matches the literals the tests
// outside this package use for the same purpose.
var fixtureVersionBase = time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)

// NextVersion returns the next version timestamp of this test's sequence, one
// second after the one before it. It is later than every version this Populator
// has handed out so far, so a caller committing a new version of a
// fixture-built document gets one that is accepted as its successor.
//
// Counted per test rather than taken from the wall clock, for the same reason
// nextDocName is: time.Now() gave a test different version values on every run,
// so a failure named a timestamp that could not be reproduced, and a second
// version built as time.Now().Add(time.Second) was only later than the first by
// however long the intervening insert happened to take.
//
// Counting is safe because a version value only has to be distinct within one
// document, and a document's ID is a fresh uu.IDv7 per fixture. Two tests
// running concurrently against the same database therefore generate the same
// version values for different documents, which collides with nothing — the
// IDs above are what keeps their rows apart, which is why those are still drawn
// unique-per-value rather than counted.
func (populator *Populator) NextVersion() docdb.VersionTime {
	populator.mu.Lock()
	defer populator.mu.Unlock()
	populator.versionSeq++
	return docdb.VersionTimeFrom(fixtureVersionBase.Add(time.Duration(populator.versionSeq) * time.Second))
}

// linkPrevVersion records version as the latest fixture version of documentID
// and returns the predecessor the new row links to, which is the version this
// fixture inserted for that document before, see DocumentVersion.
func (populator *Populator) linkPrevVersion(documentID uu.ID, version docdb.VersionTime) docdb.VersionTime {
	populator.mu.Lock()
	defer populator.mu.Unlock()
	prevVersion := docdb.VersionTimeFrom(version.Time.Add(-time.Second))
	if last, ok := populator.lastVersion[documentID]; ok {
		prevVersion = last
	}
	populator.lastVersion[documentID] = version
	return prevVersion
}

// nextDocName returns a document filename that no other fixture file of this
// test uses.
//
// These values were drawn with math/rand, which makes a name unique only by
// luck: a filename picked from rand.Int31n(10000) collided with a sibling of
// the same document version about once in 10000 runs, and the insert then
// failed on unique (document_version_id, name) — a flake that reads as a bug in
// the code under test rather than in the fixture.
//
// The counter is kept per Populator, so it is per test: the pgstore tests run
// their subtests with t.Parallel(), and a process-wide counter hands out its
// values in scheduler order, which gives a subtest different names, sizes and
// hashes on every run. Counting per test makes them reproducible instead — the
// same test produces the same values every time — and that is enough for
// uniqueness, because a filename only has to be distinct within a document
// version, whose ID is already unique.
//
// The IDs above are deliberately left unique-per-value rather than counted:
// they are what keeps the rows of concurrently running tests apart in the one
// shared database. The version timestamps used to be drawn from the wall clock
// for that same reason, which was over-cautious — see NextVersion.
func (populator *Populator) nextDocName() string {
	populator.mu.Lock()
	defer populator.mu.Unlock()
	populator.seq++
	return fmt.Sprintf("doc%d.pdf", populator.seq)
}

// nextDocFile returns the name, size and content hash of a new fixture file.
// All three describe the same imagined content, so a fixture file is internally
// consistent: its hash is the hash of content of exactly its size.
func (populator *Populator) nextDocFile() (name string, size int64, hash string) {
	name = populator.nextDocName()
	content := []byte("content of " + name)
	return name, int64(len(content)), docdb.ContentHash(content)
}

func connectFromEnv(ctx context.Context) (sqldb.Connection, error) {
	portStr := cmp.Or(os.Getenv("POSTGRES_PORT"), "5432")

	port, err := strconv.ParseUint(portStr, 10, 16)
	if err != nil {
		return nil, errs.Errorf("invalid POSTGRES_PORT: %v", err)
	}

	config := &sqldb.Config{
		Driver:   "postgres",
		Host:     "localhost",
		Port:     uint16(port),
		User:     os.Getenv("POSTGRES_USER"),
		Database: os.Getenv("POSTGRES_DB"),
		Password: cmp.Or(os.Getenv("POSTGRES_PASSWORD"), os.Getenv("PGPASSWORD")),
		Extra:    map[string]string{"sslmode": "disable"},
	}

	conn, err := pqconn.Connect(ctx, config)
	if err != nil {
		return nil, err
	}
	err = conn.Ping(ctx, 5*time.Second)
	if err != nil {
		return nil, errors.Join(err, conn.Close())
	}
	return conn, nil
}

// newFixture wraps create so its result is memoized per test: create runs at
// most once per *testing.T, and every call within that test returns the same
// value. The cache entry is dropped when the test ends.
func newFixture[V any](create func(t *testing.T) V) func(t *testing.T) V {
	var (
		mu     sync.Mutex
		values = make(map[*testing.T]V)
	)
	return func(t *testing.T) V {
		mu.Lock()
		v, cached := values[t]
		mu.Unlock()
		if cached {
			return v
		}

		v = create(t)

		mu.Lock()
		values[t] = v
		mu.Unlock()
		t.Cleanup(func() {
			mu.Lock()
			delete(values, t)
			mu.Unlock()
		})
		return v
	}
}
