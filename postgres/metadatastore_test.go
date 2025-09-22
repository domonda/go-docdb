package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math/rand"
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
		docVersion1 := populator.DocumentVersion(map[string]any{"Version": docdb.VersionTimeFrom(time.Now())})
		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		ctx := fixtureCtxWithTestTx.Value(t)

		// when
		clientCompanyId, err := store.DocumentCompanyID(
			ctx,
			docVersion1.DocumentID,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion2.ClientCompanyID, clientCompanyId)
	})

	t.Run("Returns error if document not found", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)

		// when
		_, err := store.DocumentCompanyID(
			ctx,
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
		populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		ctx := fixtureCtxWithTestTx.Value(t)

		// when
		newCompanyID := uu.IDv7()
		err := store.SetDocumentCompanyID(ctx, docVersion1.DocumentID, newCompanyID)

		// then
		require.NoError(t, err)

		savedDocumentVersions, err := db.QueryStructSlice[postgres.DocumentVersion](
			ctx,
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
		ctx := fixtureCtxWithTestTx.Value(t)

		// when
		err := store.SetDocumentCompanyID(ctx, uu.IDv7(), uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestDocumentVersions(t *testing.T) {
	t.Run("Returns all versions belonging to a document", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		populator := fixturePopulator.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)

		docVersion1 := populator.DocumentVersion()
		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		// not wanted, different doc ID
		populator.DocumentVersion()

		// when
		versions, err := store.DocumentVersions(ctx, docVersion1.DocumentID)

		// then
		require.NoError(t, err)
		require.Equal(t, 2, len(versions))
		require.Equal(t, docVersion2.Version, versions[0])
		require.Equal(t, docVersion1.Version, versions[1])
	})

	t.Run("Returns error if no versions", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)

		// when
		_, err := store.DocumentVersions(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestEnumCompanyDocumentIDs(t *testing.T) {
	t.Run("Iterates over all company related documents", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		populator := fixturePopulator.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)
		doc1Version1 := populator.DocumentVersion(map[string]any{"DocumentID": uu.IDFrom("a3c60853-022c-403d-85cc-6ea146ec6a4a")})
		populator.DocumentVersion(map[string]any{
			"DocumentID":      doc1Version1.DocumentID,
			"ClientCompanyID": doc1Version1.ClientCompanyID,
			"Version":         docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		doc2Version1 := populator.DocumentVersion(map[string]any{
			"DocumentID":      uu.IDFrom("c7e67e60-9548-43c6-83be-55cb736a5761"),
			"ClientCompanyID": doc1Version1.ClientCompanyID,
		})

		// not wanted
		populator.DocumentVersion()

		// when
		processedDocumentIDs := []uu.ID{}
		store.EnumCompanyDocumentIDs(
			ctx,
			doc1Version1.ClientCompanyID,
			func(ctx context.Context, i uu.ID) error {
				processedDocumentIDs = append(processedDocumentIDs, i)
				return nil
			},
		)

		// then
		require.Equal(t, 2, len(processedDocumentIDs))
		require.Equal(t, doc1Version1.DocumentID, processedDocumentIDs[0])
		require.Equal(t, doc2Version1.DocumentID, processedDocumentIDs[1])
	})

	t.Run("Returns error if no versions", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)

		// when
		err := store.EnumCompanyDocumentIDs(
			ctx,
			uu.IDv7(),
			func(ctx context.Context, i uu.ID) error { return nil },
		)

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})

	t.Run("Returns error from callback", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		populator := fixturePopulator.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)
		docVersion := populator.DocumentVersion()

		// when
		expectedErr := errors.New("bug")
		err := store.EnumCompanyDocumentIDs(
			ctx,
			docVersion.ClientCompanyID,
			func(ctx context.Context, i uu.ID) error {
				return expectedErr
			},
		)

		// then
		require.ErrorIs(t, err, expectedErr)
	})
}

func TestLatestDocumentVersion(t *testing.T) {
	t.Run("Returns latest docuemnt version", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		populator := fixturePopulator.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)

		docVersion1 := populator.DocumentVersion()
		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		// not wanted, different doc ID
		populator.DocumentVersion()

		// when
		version, err := store.LatestDocumentVersion(ctx, docVersion1.DocumentID)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion2.Version, version)
	})

	t.Run("Returns error if no version found", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)

		// when
		_, err := store.LatestDocumentVersion(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestDocumentVersionInfo(t *testing.T) {
	t.Run("Returns document version info", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)
		populator := fixturePopulator.Value(t)
		docVersionFile1 := populator.DocumentVersionFile()

		docVersionFile2 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": docVersionFile1.DocumentVersion,
		})

		// not wanted
		populator.DocumentVersionFile()

		// when
		versionInfo, err := store.DocumentVersionInfo(
			ctx,
			docVersionFile1.DocumentVersion.DocumentID,
			docVersionFile1.DocumentVersion.Version,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersionFile1.DocumentVersion.DocumentID, versionInfo.DocID)
		require.Equal(t, docVersionFile1.DocumentVersion.ClientCompanyID, versionInfo.CompanyID)
		require.Equal(t, docVersionFile1.DocumentVersion.Version, versionInfo.Version)
		require.Equal(t, *docVersionFile1.DocumentVersion.PrevVersion, versionInfo.PrevVersion)
		require.Equal(t, docVersionFile1.DocumentVersion.AddedFiles, versionInfo.AddedFiles)
		require.Equal(t, docVersionFile1.DocumentVersion.ModifiedFiles, versionInfo.ModifiedFiles)
		require.Equal(t, docVersionFile1.DocumentVersion.RemovedFiles, versionInfo.RemovedFiles)

		require.Equal(t, 2, len(versionInfo.Files))

		file := versionInfo.Files[docVersionFile1.Name]
		require.Equal(t, docVersionFile1.Name, file.Name)
		require.Equal(t, docVersionFile1.Hash, file.Hash)
		require.Equal(t, docVersionFile1.Size, file.Size)

		file = versionInfo.Files[docVersionFile2.Name]
		require.Equal(t, docVersionFile2.Name, file.Name)
		require.Equal(t, docVersionFile2.Hash, file.Hash)
		require.Equal(t, docVersionFile2.Size, file.Size)
	})

	t.Run("Returns error if no version info found", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)

		// when
		_, err := store.DocumentVersionInfo(ctx, uu.IDv7(), docdb.VersionTimeFrom(time.Now()))

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestLatestDocumentVersionInfo(t *testing.T) {
	t.Run("Returns latest document version info", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)
		populator := fixturePopulator.Value(t)
		// older, not wanted
		docVersion1File := populator.DocumentVersionFile()

		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1File.DocumentVersion.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})

		// expected
		docVersion2File1 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": docVersion2,
		})
		docVersion2File2 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": docVersion2,
		})

		// not wanted
		populator.DocumentVersionFile()

		// when
		versionInfo, err := store.LatestDocumentVersionInfo(
			ctx,
			docVersion2.DocumentID,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion2.DocumentID, versionInfo.DocID)
		require.Equal(t, docVersion2.ClientCompanyID, versionInfo.CompanyID)
		require.Equal(t, docVersion2.Version, versionInfo.Version)
		require.Equal(t, *docVersion2.PrevVersion, versionInfo.PrevVersion)
		require.Equal(t, docVersion2.AddedFiles, versionInfo.AddedFiles)
		require.Equal(t, docVersion2.ModifiedFiles, versionInfo.ModifiedFiles)
		require.Equal(t, docVersion2.RemovedFiles, versionInfo.RemovedFiles)

		require.Equal(t, 2, len(versionInfo.Files))

		file := versionInfo.Files[docVersion2File1.Name]
		require.Equal(t, docVersion2File1.Name, file.Name)
		require.Equal(t, docVersion2File1.Hash, file.Hash)
		require.Equal(t, docVersion2File1.Size, file.Size)

		file = versionInfo.Files[docVersion2File2.Name]
		require.Equal(t, docVersion2File2.Name, file.Name)
		require.Equal(t, docVersion2File2.Hash, file.Hash)
		require.Equal(t, docVersion2File2.Size, file.Size)
	})

	t.Run("Returns error if no version info found", func(t *testing.T) {
		// given
		store := fixtureStore.Value(t)
		ctx := fixtureCtxWithTestTx.Value(t)

		// when
		_, err := store.LatestDocumentVersion(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

var fixtureStore = fix.New(func(t *testing.T) docdb.MetadataStore {
	return postgres.NewMetadataStore()
})

var fixtureCtxWithTestTx = fix.New(func(t *testing.T) context.Context {
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

	ctx := db.ContextWithConn(t.Context(), conn)

	t.Cleanup(func() { conn.Rollback() })
	return ctx
})

var fixturePopulator = fix.New(func(t *testing.T) Populator {
	return Populator{
		t:   t,
		ctx: fixtureCtxWithTestTx.Value(t),
	}
})

type Populator struct {
	t   *testing.T
	ctx context.Context
}

func (populator *Populator) DocumentVersion(data ...map[string]any) *postgres.DocumentVersion {
	baseRecord := &postgres.DocumentVersion{
		ID:              uu.IDv7(),
		DocumentID:      uu.IDv7(),
		ClientCompanyID: uu.IDv7(),
		Version:         docdb.VersionTimeFrom(time.Now()),
		PrevVersion:     p(docdb.VersionTimeFrom(time.Now().Add(-time.Second))),
		CommitUserID:    uu.IDv7(),
		CommitReason:    "test",
		AddedFiles:      []string{randomDocName(), randomDocName()},
		ModifiedFiles:   []string{randomDocName(), randomDocName()},
		RemovedFiles:    []string{randomDocName(), randomDocName()},
	}

	insertRecordWithExtraData(populator, "docdb.document_version", baseRecord, data...)
	return baseRecord
}

func (populator *Populator) DocumentVersionFile(data ...map[string]any) *postgres.DocumentVersionFile {
	docVersion := createRecordIfNeeded("DocumentVersion", populator.DocumentVersion, data...)
	baseRecord := &postgres.DocumentVersionFile{
		DocumentVersionID: docVersion.ID,
		Name:              randomDocName(),
		Size:              rand.Int63n(10000),
		Hash:              docdb.ContentHash(uu.IDv7().Bytes()),
		DocumentVersion:   docVersion,
	}

	insertRecordWithExtraData(populator, "docdb.document_version_file", baseRecord, data...)
	return baseRecord
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
		p.ctx,
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
		if !field.IsValid() {
			continue
		}
		newVal := reflect.ValueOf(value)
		field.Set(newVal)
	}
}

func randomDocName() string {
	return fmt.Sprintf("doc%d.pdf", rand.Int31n(10000))
}

func p[T any](v T) *T { return &v }
