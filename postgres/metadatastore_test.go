package postgres_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/postgres"
	"github.com/domonda/go-docdb/postgres/pgfixtures"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/uu"
)

var store = postgres.NewMetadataStore()

func TestCreateDocument(t *testing.T) {
	t.Run("Creates document version with proper file metadata", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		version := docdb.NewVersionTime()

		memFiles := []fs.MemFile{
			{
				FileName: "doc1.pdf",
				FileData: []byte("a"),
			},
			{
				FileName: "doc2.pdf",
				FileData: []byte("b"),
			},
		}

		// when
		versionInfo, err := store.CreateDocument(
			ctx,
			uu.IDv7(),
			uu.IDv7(),
			uu.IDv7(),
			"reason",
			version,
			[]fs.FileReader{memFiles[0], memFiles[1]},
		)

		// then
		require.NoError(t, err)
		require.Equal(t, []string{memFiles[0].FileName, memFiles[1].FileName}, versionInfo.AddedFiles)
		require.Nil(t, versionInfo.ModifiedFiles)
		require.Nil(t, versionInfo.RemovedFiles)
		require.Equal(t, docdb.VersionTime{}, versionInfo.PrevVersion)

		savedFiles, err := db.QueryStructSlice[postgres.DocumentVersionFile](
			ctx,
			/* sql */ `
			select dvf.* from docdb.document_version_file dvf
			join docdb.document_version dv
				on dv.document_id = $1
				and dv.company_id = $2
				and dv.version = $3
				and dvf.document_version_id = dv.id
			order by dvf.name
			`,
			versionInfo.DocID,
			versionInfo.CompanyID,
			versionInfo.Version,
		)

		require.NoError(t, err)
		require.Equal(t, 2, len(savedFiles))

		require.Equal(t, memFiles[0].FileName, savedFiles[0].Name)
		require.Equal(
			t,
			docdb.ContentHash(memFiles[0].FileData),
			savedFiles[0].Hash,
		)

		require.Equal(t, memFiles[1].FileName, savedFiles[1].Name)
		require.Equal(
			t,
			docdb.ContentHash(memFiles[1].FileData),
			savedFiles[1].Hash,
		)
	})
}

func TestDocumentCompanyID(t *testing.T) {

	// In theory all versions should have the same company_id, but if not, return the company_id from the most recent version
	t.Run("Returns company ID from the latest version", func(t *testing.T) {
		// given
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		docVersion1 := populator.DocumentVersion()
		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		clientCompanyId, err := store.DocumentCompanyID(
			ctx,
			docVersion1.DocumentID,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion2.CompanyID, clientCompanyId)
	})

	t.Run("Returns error if document not found", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

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
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		docVersion1 := populator.DocumentVersion()
		populator.DocumentVersion(map[string]any{
			"DocumentID": docVersion1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

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
			require.Equal(t, newCompanyID, savedDocumentVersions[i].CompanyID)
		}
	})

	t.Run("Returns error if document version does not exist", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		err := store.SetDocumentCompanyID(ctx, uu.IDv7(), uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestDocumentVersions(t *testing.T) {
	t.Run("Returns all versions belonging to a document", func(t *testing.T) {
		// given
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

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
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		_, err := store.DocumentVersions(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestEnumCompanyDocumentIDs(t *testing.T) {
	t.Run("Iterates over all company related documents", func(t *testing.T) {
		// given
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		doc1Version1 := populator.DocumentVersion(map[string]any{"DocumentID": uu.IDFrom("a3c60853-022c-403d-85cc-6ea146ec6a4a")})
		populator.DocumentVersion(map[string]any{
			"DocumentID": doc1Version1.DocumentID,
			"CompanyID":  doc1Version1.CompanyID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		doc2Version1 := populator.DocumentVersion(map[string]any{
			"DocumentID": uu.IDFrom("c7e67e60-9548-43c6-83be-55cb736a5761"),
			"CompanyID":  doc1Version1.CompanyID,
		})

		// not wanted
		populator.DocumentVersion()

		// when
		processedDocumentIDs := []uu.ID{}
		store.EnumCompanyDocumentIDs(
			ctx,
			doc1Version1.CompanyID,
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

	t.Run("Returns no error if no versions", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		err := store.EnumCompanyDocumentIDs(
			ctx,
			uu.IDv7(),
			func(ctx context.Context, i uu.ID) error { return nil },
		)

		// then
		require.NoError(t, err)
	})

	t.Run("Returns error from callback", func(t *testing.T) {
		// given
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		docVersion := populator.DocumentVersion()

		// when
		expectedErr := errors.New("bug")
		err := store.EnumCompanyDocumentIDs(
			ctx,
			docVersion.CompanyID,
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
		t.Parallel()
		populator := pgfixtures.FixturePopulator(t)
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

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
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		_, err := store.LatestDocumentVersion(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestDocumentVersionInfo(t *testing.T) {
	t.Run("Returns document version info", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
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
		require.Equal(t, docVersionFile1.DocumentVersion.CompanyID, versionInfo.CompanyID)
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

	t.Run("Returns document version info without files", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		docVersion := populator.DocumentVersion()

		// not wanted
		populator.DocumentVersionFile()

		// when
		versionInfo, err := store.DocumentVersionInfo(
			ctx,
			docVersion.DocumentID,
			docVersion.Version,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion.DocumentID, versionInfo.DocID)
		require.Equal(t, docVersion.CompanyID, versionInfo.CompanyID)
		require.Equal(t, docVersion.Version, versionInfo.Version)
		require.Equal(t, *docVersion.PrevVersion, versionInfo.PrevVersion)
		require.Equal(t, docVersion.AddedFiles, versionInfo.AddedFiles)
		require.Equal(t, docVersion.ModifiedFiles, versionInfo.ModifiedFiles)
		require.Equal(t, docVersion.RemovedFiles, versionInfo.RemovedFiles)
	})

	t.Run("Returns error if no version info found", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		_, err := store.DocumentVersionInfo(ctx, uu.IDv7(), docdb.VersionTimeFrom(time.Now()))

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestLatestDocumentVersionInfo(t *testing.T) {
	t.Run("Returns latest document version info", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
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
		require.Equal(t, docVersion2.CompanyID, versionInfo.CompanyID)
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

	t.Run("Returns latest document version info without files", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		docVersion := populator.DocumentVersion()

		// not wanted
		populator.DocumentVersionFile()

		// when
		versionInfo, err := store.LatestDocumentVersionInfo(
			ctx,
			docVersion.DocumentID,
		)

		// then
		require.NoError(t, err)
		require.Equal(t, docVersion.DocumentID, versionInfo.DocID)
		require.Equal(t, docVersion.CompanyID, versionInfo.CompanyID)
		require.Equal(t, docVersion.Version, versionInfo.Version)
		require.Equal(t, *docVersion.PrevVersion, versionInfo.PrevVersion)
		require.Equal(t, docVersion.AddedFiles, versionInfo.AddedFiles)
		require.Equal(t, docVersion.ModifiedFiles, versionInfo.ModifiedFiles)
		require.Equal(t, docVersion.RemovedFiles, versionInfo.RemovedFiles)
	})

	t.Run("Returns error if no version info found", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		_, err := store.LatestDocumentVersion(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestDeleteDocument(t *testing.T) {
	t.Run("Deletes document versions", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		doc1Version1 := populator.DocumentVersion()
		populator.DocumentVersion(map[string]any{
			"DocumentID": doc1Version1.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})

		doc2Version := populator.DocumentVersion()

		// when
		err := store.DeleteDocument(ctx, doc1Version1.DocumentID)

		// then
		require.NoError(t, err)
		count, err := db.QueryValue[int](
			ctx,
			/* sql */ `select count(*) from docdb.document_version where document_id = $1`,
			doc1Version1.DocumentID,
		)
		require.NoError(t, err)
		require.Equal(t, 0, count)

		count, err = db.QueryValue[int](
			ctx,
			/* sql */ `select count(*) from docdb.document_version where document_id = $1`,
			doc2Version.DocumentID,
		)
		require.NoError(t, err)
		require.Equal(t, 1, count)
	})

	t.Run("Returns error if nothing to delete", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		err := store.DeleteDocument(ctx, uu.IDv7())

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}

func TestDeleteDocumentVersion(t *testing.T) {
	t.Run("Deletes document version", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)
		populator := pgfixtures.FixturePopulator(t)
		versionFile1 := populator.DocumentVersionFile(map[string]any{
			"Hash": docdb.ContentHash([]byte("b")),
		})
		versionFile2 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": versionFile1.DocumentVersion,
			"Hash":            docdb.ContentHash([]byte("a")),
		})

		docVersion2 := populator.DocumentVersion(map[string]any{
			"DocumentID": versionFile1.DocumentVersion.DocumentID,
			"Version":    docdb.VersionTimeFrom(time.Now().Add(time.Second)),
		})
		versionFile3 := populator.DocumentVersionFile(map[string]any{
			"DocumentVersion": docVersion2,
		})

		// when
		leftVersions, hashesToDelete, err := store.DeleteDocumentVersion(
			ctx,
			versionFile1.DocumentVersion.DocumentID,
			versionFile1.DocumentVersion.Version,
		)

		// then
		require.NoError(t, err)

		require.Equal(
			t,
			[]string{versionFile1.Hash, versionFile2.Hash},
			hashesToDelete,
		)
		require.Equal(
			t,
			[]docdb.VersionTime{versionFile3.DocumentVersion.Version},
			leftVersions,
		)
	})

	t.Run("Returns error if nothing to delete", func(t *testing.T) {
		// given
		t.Parallel()
		ctx := pgfixtures.FixtureCtxWithTestTx(t)

		// when
		_, _, err := store.DeleteDocumentVersion(ctx, uu.IDv7(), docdb.VersionTimeFrom(time.Now()))

		// then
		require.ErrorIs(t, err, sql.ErrNoRows)
	})
}
