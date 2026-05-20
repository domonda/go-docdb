// Provides test fixtures for the pgstore package

package pgfixtures

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"math/rand"
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
// Connection and ping failures are returned rather than panicked, so tests
// can skip cleanly when no database is available (e.g. plain `go test ./...`).
var globalConn = sync.OnceValues(func() (sqldb.Connection, error) {
	return connectFromEnv(context.Background())
})

// CloseGlobalConn closes the process-wide test database connection
// if one was successfully opened.
func CloseGlobalConn() {
	if conn, err := globalConn(); err == nil {
		conn.Close() //#nosec G104
	}
}

var FixtureGlobalConn = newFixture(func(t *testing.T) sqldb.Connection {
	conn, err := globalConn()
	if err != nil {
		t.Skipf("Postgres test database not available: %v", err)
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
	return insertRecordWithExtraData(
		pgstore.DocumentVersion{
			ID:            uu.IDv7(),
			DocumentID:    uu.IDv7(),
			CompanyID:     uu.IDv7(),
			Version:       docdb.VersionTimeFrom(time.Now()),
			PrevVersion:   new(docdb.VersionTimeFrom(time.Now().Add(-time.Second))),
			CommitUserID:  uu.IDv7(),
			CommitReason:  "test",
			AddedFiles:    []string{randomDocName(), randomDocName()},
			ModifiedFiles: []string{randomDocName(), randomDocName()},
			RemovedFiles:  []string{randomDocName(), randomDocName()},
		}, populator, data...)
}

func (populator *Populator) DocumentVersionFile(data ...map[string]any) *pgstore.DocumentVersionFile {
	docVersion := createRecordIfNeeded("DocumentVersion", populator.DocumentVersion, data...)

	return insertRecordWithExtraData(
		pgstore.DocumentVersionFile{
			DocumentVersionID: docVersion.ID,
			Name:              randomDocName(),
			Size:              rand.Int63n(10000), //#nosec G404
			Hash:              docdb.ContentHash(uu.IDv7().Bytes()),
			DocumentVersion:   docVersion,
		}, populator, data...)
}

func createRecordIfNeeded[T any](
	key string,
	createRecord func(data ...map[string]any) *T,
	data ...map[string]any,
) *T {
	d := map[string]any{}
	if len(data) > 0 {
		d = data[0]
	}

	if res, ok := d[key]; ok {
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
	d := map[string]any{}
	if len(data) > 0 {
		d = data[0]
	}

	ref := reflect.ValueOf(&obj).Elem()
	for key, value := range d {
		field := ref.FieldByName(key)
		if !field.IsValid() {
			continue
		}
		newVal := reflect.ValueOf(value)
		field.Set(newVal)
	}
	return &obj
}

func randomDocName() string {
	return fmt.Sprintf("doc%d.pdf", rand.Int31n(10000)) //#nosec G404
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
	if err := conn.Ping(ctx, 5*time.Second); err != nil {
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
