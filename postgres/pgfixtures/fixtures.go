// Provides test fixtures for the postgres package

package pgfixtures

import (
	"cmp"
	"context"
	"fmt"
	"math/rand"
	"os"
	"reflect"
	"strconv"
	"testing"
	"time"

	"github.com/datek/fix"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/postgres"
	"github.com/domonda/go-errs"
	"github.com/domonda/go-sqldb"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-sqldb/pqconn"
	"github.com/domonda/go-types/uu"
)

var conn sqldb.Connection

func CloseGlobalConn() {
	if conn != nil {
		conn.Close() //#nosec G104
	}
}

var FixtureGlobalConn = fix.New(func(t *testing.T) sqldb.Connection {
	if conn != nil {
		return conn
	}

	conn = newConnFromEnv(t.Context())
	return conn
})

var FixtureCtxWithTestTx = fix.New(func(t *testing.T) context.Context {
	tx, err := FixtureGlobalConn(t).Begin(t.Context(), sqldb.NextTransactionID(), nil)
	if err != nil {
		t.Fatalf("Failed to begin the transaction, %v", err)
		return nil
	}

	t.Cleanup(func() { tx.Rollback() }) //#nosec G104
	ctx := db.ContextWithConn(t.Context(), tx)
	return ctx
})

var FixturePopulator = fix.New(func(t *testing.T) *Populator {
	return &Populator{
		t:   t,
		ctx: FixtureCtxWithTestTx(t),
	}
})

type Populator struct {
	t   *testing.T
	ctx context.Context
}

func (populator *Populator) DocumentVersion(data ...map[string]any) *postgres.DocumentVersion {
	return insertRecordWithExtraData(
		postgres.DocumentVersion{
			ID:            uu.IDv7(),
			DocumentID:    uu.IDv7(),
			CompanyID:     uu.IDv7(),
			Version:       docdb.VersionTimeFrom(time.Now()),
			PrevVersion:   p(docdb.VersionTimeFrom(time.Now().Add(-time.Second))),
			CommitUserID:  uu.IDv7(),
			CommitReason:  "test",
			AddedFiles:    []string{randomDocName(), randomDocName()},
			ModifiedFiles: []string{randomDocName(), randomDocName()},
			RemovedFiles:  []string{randomDocName(), randomDocName()},
		}, populator, data...)
}

func (populator *Populator) DocumentVersionFile(data ...map[string]any) *postgres.DocumentVersionFile {
	docVersion := createRecordIfNeeded("DocumentVersion", populator.DocumentVersion, data...)

	return insertRecordWithExtraData(
		postgres.DocumentVersionFile{
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

func p[T any](v T) *T { return &v }

func newConnFromEnv(ctx context.Context) sqldb.Connection {
	portStr := cmp.Or(os.Getenv("POSTGRES_PORT"), "5432")

	port, err := strconv.ParseUint(portStr, 10, 16)
	if err != nil {
		panic(errs.Errorf("invalid POSTGRES_PORT: %v", err))
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
		panic(err)
	}

	return conn
}
