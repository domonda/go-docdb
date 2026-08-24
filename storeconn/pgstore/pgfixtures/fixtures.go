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
	"sync/atomic"
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
		t:   t,
		ctx: FixtureCtxWithTestTx(t),
	}
})

type Populator struct {
	t   *testing.T
	ctx context.Context
}

func (populator *Populator) DocumentVersion(data ...map[string]any) *pgstore.DocumentVersion {
	// Derive the predecessor from this row's own version rather than from the
	// wall clock, so two versions of one document never name the same
	// predecessor: a caller that overrides Version to build a multi-version
	// document would otherwise produce a forked chain, which the
	// one-successor-per-version index rejects.
	version := docdb.VersionTimeFrom(time.Now())
	if v, ok := mergedData(data...)["Version"].(docdb.VersionTime); ok {
		version = v
	}
	return insertRecordWithExtraData(
		pgstore.DocumentVersion{
			ID:            uu.IDv7(),
			DocumentID:    uu.IDv7(),
			CompanyID:     uu.IDv7(),
			Version:       version,
			PrevVersion:   new(docdb.VersionTimeFrom(version.Time.Add(-time.Second))),
			CommitUserID:  uu.IDv7(),
			CommitReason:  "test",
			AddedFiles:    []string{nextDocName(), nextDocName()},
			ModifiedFiles: []string{nextDocName(), nextDocName()},
			RemovedFiles:  []string{nextDocName(), nextDocName()},
		}, populator, data...)
}

func (populator *Populator) DocumentVersionFile(data ...map[string]any) *pgstore.DocumentVersionFile {
	docVersion := createRecordIfNeeded("DocumentVersion", populator.DocumentVersion, data...)

	name, size, hash := nextDocFile()
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

// fixtureSeq numbers the file values generated below.
//
// They were drawn with math/rand, which makes a name unique only by luck: a
// filename picked from rand.Int31n(10000) collided with a sibling of the same
// document version about once in 10000 runs, and the insert then failed on
// unique (document_version_id, name) — a flake that reads as a bug in the code
// under test rather than in the fixture. A counter cannot collide, and it makes
// a run reproducible: the same test produces the same names, sizes and hashes
// every time.
//
// The IDs and version timestamps above are deliberately left unique-per-value
// rather than counted. They have to be distinct across concurrently running
// test binaries sharing one database, which a per-process counter cannot
// guarantee. Filenames only have to be distinct within a document version,
// whose ID is already unique, so counting them is enough.
var fixtureSeq atomic.Int64

// nextDocName returns a document filename that no other fixture of this
// process uses.
func nextDocName() string {
	return fmt.Sprintf("doc%d.pdf", fixtureSeq.Add(1))
}

// nextDocFile returns the name, size and content hash of a new fixture file.
// All three describe the same imagined content, so a fixture file is internally
// consistent: its hash is the hash of content of exactly its size.
func nextDocFile() (name string, size int64, hash string) {
	name = nextDocName()
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
