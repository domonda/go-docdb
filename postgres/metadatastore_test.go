package postgres_test

import (
	"database/sql"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/datek/fix"
	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/postgres"
	"github.com/domonda/go-sqldb"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-sqldb/pqconn"
	"github.com/domonda/go-types/uu"
	"github.com/stretchr/testify/require"
)

func TestDocumentCompanyID(t *testing.T) {

	// In theory all versions should have the same company_id, but if not, return the company_id from the most recent version
	t.Run("Returns company ID from the latest version", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		populator := fixturePopulator.Value(t)
		docVersion1 := populator.DocumentVersion(map[string]any{"Version": time.Now()})
		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    time.Now().Add(time.Second),
		})

		// when
		clientCompanyId, err := store.DocumentCompanyID(
			t.Context(),
			docVersion1.DocumentID,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion2.ClientCompanyID, clientCompanyId)
	})

	t.Run("Returns error if document not found", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)

		// when
		_, err := store.DocumentCompanyID(
			t.Context(),
			uu.IDv7(),
		)

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestSetDocumentCompanyID(t *testing.T) {
	t.Run("Sets the company ID for all versions", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		populator := fixturePopulator.Value(t)
		docVersion1 := populator.DocumentVersion()
		populator.DocumentVersion(map[string]any{"DocumentID": docVersion1.DocumentID})

		// when
		newCompanyID := uu.IDv7()
		err := store.SetDocumentCompanyID(t.Context(), docVersion1.DocumentID, newCompanyID)

		// then
		require.NoError(t, err)

		savedDocumentVersions, err := db.QueryStructSlice[postgres.DocumentVersion](
			t.Context(),
			/* sql */ `select * from docdb.document_version where document_id = $1`,
			docVersion1.DocumentID,
		)
		require.NoError(t, err)
		require.Equal(t, 2, len(savedDocumentVersions))
		for i := range 2 {
			require.Equal(t, newCompanyID, savedDocumentVersions[i].ClientCompanyID)
		}
	})

	t.Run("Returns error if document version does not exist", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)

		// when
		err := store.SetDocumentCompanyID(t.Context(), uu.IDv7(), uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

var fixtureStore = fix.New(func(t *testing.T) docdb.MetadataStore {
	fixtureTestTx.Value(t)
	return postgres.NewMetadataStore()
})

var fixtureTestTx = fix.New(func(t *testing.T) any {
	config := &sqldb.Config{
		Driver:   "postgres",
		Host:     "localhost",
		User:     os.Getenv("POSTGRES_USER"),
		Database: os.Getenv("POSTGRES_DB"),
		Password: os.Getenv("POSTGRES_PASSWORD"),
		Extra:    map[string]string{"sslmode": "disable"},
	}

	conn, err := pqconn.New(t.Context(), config)
	if err != nil {
		t.Fatalf("Failed to connect to postgres, %v", err)
		return nil
	}

	conn, err = conn.Begin(nil, 0)
	if err != nil {
		t.Fatalf("Failed to begin the transaction, %v", err)
		return nil
	}

	db.SetConn(conn)
	t.Cleanup(func() { conn.Rollback() })
	return nil
})

var fixturePopulator = fix.New(func(t *testing.T) Populator {
	fixtureTestTx.Value(t)
	return Populator{t}
})

type Populator struct {
	t *testing.T
}

func (p *Populator) DocumentVersion(data ...map[string]any) *postgres.DocumentVersion {
	baseRecord := &postgres.DocumentVersion{
		ID:              uu.IDv7(),
		DocumentID:      uu.IDv7(),
		ClientCompanyID: uu.IDv7(),
		Version:         time.Now(),
		CommitUserID:    uu.IDv7(),
		CommitReason:    "test",
	}
	insertRecordWithExtraData(p, "docdb.document_version", baseRecord, data...)
	return baseRecord
}

func insertRecordWithExtraData[T any](
	p *Populator,
	table string,
	baseRecord *T,
	data ...map[string]any,
) {
	fillDataIntoStruct(
		baseRecord,
		data...,
	)

	err := db.InsertStruct(
		p.t.Context(),
		table,
		baseRecord,
	)

	if err != nil {
		p.t.Fatalf("Failed to insert into table '%s', %v", table, err)
	}
}

func fillDataIntoStruct[T any](base *T, data ...map[string]any) {
	d := map[string]any{}

	if len(data) > 0 {
		d = data[0]
	}

	obj := reflect.ValueOf(base).Elem()
	for key, value := range d {
		field := obj.FieldByName(key)
		newVal := reflect.ValueOf(value)
		field.Set(newVal)
	}
}
