package integrationtests

import (
	"context"
	"testing"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/postgres"
	"github.com/domonda/go-docdb/postgres/pgfixtures"
	"github.com/domonda/go-docdb/s3"
	"github.com/domonda/go-docdb/s3/s3fixtures"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/uu"
	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"
)

func TestConn(t *testing.T) {
	t.Run("Test AddDocumentVersion with postgres and S3", func(t *testing.T) {
		t.Run("Adds new files to the new version", func(t *testing.T) {
			// given
			bucketName := s3fixtures.FixtureCleanBucket(t)
			documentStore, err := s3.NewS3DocumentStore(bucketName)
			require.NoError(t, err)
			conn := docdb.NewConn(
				documentStore,
				postgres.NewMetadataStore(),
			)
			populator := pgfixtures.FixturePopulator(t)
			documentVersionFile := populator.DocumentVersionFile()

			newFile := fs.NewMemFile("doc-a.pdf", []byte("a"))
			var createVersion docdb.CreateVersionFunc = func(
				ctx context.Context,
				prevVersion docdb.VersionTime,
				prevFiles docdb.FileProvider,
			) (
				writeFiles []fs.FileReader,
				removeFiles []string,
				newCompanyID *uu.ID,
				err error,
			) {
				writeFiles = append(writeFiles, newFile)

				return writeFiles, removeFiles, newCompanyID, nil
			}

			newVersion := &docdb.VersionInfo{}
			var onNewVersion docdb.OnNewVersionFunc = func(ctx context.Context, versionInfo *docdb.VersionInfo) error {
				newVersion = versionInfo
				return nil
			}

			ctx := pgfixtures.FixtureCtxWithTestTx(t)

			// when
			err = conn.AddDocumentVersion(
				ctx,
				documentVersionFile.DocumentVersion.DocumentID,
				uu.IDv7(),
				"reason",
				createVersion,
				onNewVersion,
			)

			// then
			require.NoError(t, err)
			require.Equal(t, 1, len(newVersion.AddedFiles))
			require.Equal(t, 0, len(newVersion.RemovedFiles))
			require.Equal(t, 0, len(newVersion.ModifiedFiles))

			objectExists := s3fixtures.FixtureObjextExists(t)
			require.True(t, objectExists(newVersion.DocID, newVersion.AddedFiles[0], docdb.ContentHash(newFile.FileData)))

			res, err := db.QueryValue[int](
				ctx,
				/* sql */ `
				select count(*) from docdb.document_version_file dvf
				join docdb.document_version dv
					on dv.id = dvf.document_version_id
					and dv.document_id = $1
					and dv.version = $2
					and dv.prev_version = $3
				`,
				newVersion.DocID,
				newVersion.Version,
				documentVersionFile.DocumentVersion.Version,
			)
			require.NoError(t, err)
			require.Equal(t, 1, res)
		})

		t.Run("Adds modified files to the new version", func(t *testing.T) {
			// given
			documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
			conn := docdb.NewConn(
				documentStore,
				postgres.NewMetadataStore(),
			)
			populator := pgfixtures.FixturePopulator(t)
			content := []byte("a")
			documentVersionFile := populator.DocumentVersionFile(map[string]any{"Hash": docdb.ContentHash(content)})
			createDocument := s3fixtures.FixtureCreateDocument(t)

			createDocument(
				documentVersionFile.DocumentVersion.DocumentID,
				documentVersionFile.Name,
				content,
			)

			modifiedFile := fs.NewMemFile(documentVersionFile.Name, []byte("b"))

			var createVersion docdb.CreateVersionFunc = func(
				ctx context.Context,
				prevVersion docdb.VersionTime,
				prevFiles docdb.FileProvider,
			) (
				writeFiles []fs.FileReader,
				removeFiles []string,
				newCompanyID *uu.ID,
				err error,
			) {
				writeFiles = append(writeFiles, modifiedFile)

				return writeFiles, removeFiles, newCompanyID, nil
			}

			newVersion := &docdb.VersionInfo{}
			var onNewVersion docdb.OnNewVersionFunc = func(ctx context.Context, versionInfo *docdb.VersionInfo) error {
				newVersion = versionInfo
				return nil
			}

			ctx := pgfixtures.FixtureCtxWithTestTx(t)

			// when
			err := conn.AddDocumentVersion(
				ctx,
				documentVersionFile.DocumentVersion.DocumentID,
				uu.IDv7(),
				"reason",
				createVersion,
				onNewVersion,
			)

			// then
			require.NoError(t, err)
			require.Equal(t, 0, len(newVersion.AddedFiles))
			require.Equal(t, 0, len(newVersion.RemovedFiles))
			require.Equal(t, 1, len(newVersion.ModifiedFiles))

			objectExists := s3fixtures.FixtureObjextExists(t)
			require.True(t, objectExists(newVersion.DocID, newVersion.ModifiedFiles[0], docdb.ContentHash(modifiedFile.FileData)))

			res, err := db.QueryValue[int](
				ctx,
				/* sql */ `
				select count(*) from docdb.document_version_file dvf
				join docdb.document_version dv
					on dv.id = dvf.document_version_id
					and dv.document_id = $1
					and dv.version = $2
					and dv.prev_version = $3
				`,
				newVersion.DocID,
				newVersion.Version,
				documentVersionFile.DocumentVersion.Version,
			)
			require.NoError(t, err)
			require.Equal(t, 1, res)
		})

		t.Run("Adds removed files to the new version", func(t *testing.T) {
			// given
			documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
			conn := docdb.NewConn(
				documentStore,
				postgres.NewMetadataStore(),
			)
			populator := pgfixtures.FixturePopulator(t)
			content := []byte("a")
			documentVersionFile := populator.DocumentVersionFile(map[string]any{"Hash": docdb.ContentHash(content)})
			createDocument := s3fixtures.FixtureCreateDocument(t)

			createDocument(
				documentVersionFile.DocumentVersion.DocumentID,
				documentVersionFile.Name,
				content,
			)

			var createVersion docdb.CreateVersionFunc = func(
				ctx context.Context,
				prevVersion docdb.VersionTime,
				prevFiles docdb.FileProvider,
			) (
				writeFiles []fs.FileReader,
				removeFiles []string,
				newCompanyID *uu.ID,
				err error,
			) {
				removeFiles = append(removeFiles, documentVersionFile.Name)
				return writeFiles, removeFiles, newCompanyID, nil
			}

			newVersion := &docdb.VersionInfo{}
			var onNewVersion docdb.OnNewVersionFunc = func(ctx context.Context, versionInfo *docdb.VersionInfo) error {
				newVersion = versionInfo
				return nil
			}

			ctx := pgfixtures.FixtureCtxWithTestTx(t)

			// when
			err := conn.AddDocumentVersion(
				ctx,
				documentVersionFile.DocumentVersion.DocumentID,
				uu.IDv7(),
				"reason",
				createVersion,
				onNewVersion,
			)

			// then
			require.NoError(t, err)
			require.Equal(t, 0, len(newVersion.AddedFiles))
			require.Equal(t, 1, len(newVersion.RemovedFiles))
			require.Equal(t, 0, len(newVersion.ModifiedFiles))
			objectExists := s3fixtures.FixtureObjextExists(t)
			require.True(t, objectExists(newVersion.DocID, newVersion.RemovedFiles[0], documentVersionFile.Hash))

			res, err := db.QueryValue[int](
				ctx,
				/* sql */ `
				select count(*) from docdb.document_version_file dvf
				join docdb.document_version dv
					on dv.id = dvf.document_version_id
					and dv.document_id = $1
					and dv.version = $2
					and dv.prev_version = $3
				`,
				newVersion.DocID,
				newVersion.Version,
				documentVersionFile.DocumentVersion.Version,
			)
			require.NoError(t, err)
			require.Equal(t, 0, res)
		})

		t.Run("Basic document version data is correct", func(t *testing.T) {
			// given
			documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
			conn := docdb.NewConn(
				documentStore,
				postgres.NewMetadataStore(),
			)
			populator := pgfixtures.FixturePopulator(t)
			documentVersion := populator.DocumentVersion()
			companyID := uu.IDv7()

			var createVersion docdb.CreateVersionFunc = func(
				ctx context.Context,
				prevVersion docdb.VersionTime,
				prevFiles docdb.FileProvider,
			) (
				writeFiles []fs.FileReader,
				removeFiles []string,
				newCompanyID *uu.ID,
				err error,
			) {
				return writeFiles, removeFiles, &companyID, nil
			}

			newVersion := &docdb.VersionInfo{}
			var onNewVersion docdb.OnNewVersionFunc = func(ctx context.Context, versionInfo *docdb.VersionInfo) error {
				newVersion = versionInfo
				return nil
			}

			ctx := pgfixtures.FixtureCtxWithTestTx(t)

			// when
			err := conn.AddDocumentVersion(
				ctx,
				documentVersion.DocumentID,
				uu.IDv7(),
				"reason",
				createVersion,
				onNewVersion,
			)
			require.NoError(t, err)

			// then
			savedNewVersion, err := db.QueryRowStruct[postgres.DocumentVersion](
				ctx,
				/* sql */ `
				select * from docdb.document_version
					where document_id = $1
					and version = $2`,
				newVersion.DocID,
				newVersion.Version,
			)
			require.NoError(t, err)
			require.Equal(t, newVersion.CommitUserID, savedNewVersion.CommitUserID)
			require.Equal(t, newVersion.CommitReason, savedNewVersion.CommitReason)
			require.Equal(t, newVersion.CompanyID, savedNewVersion.CompanyID)
			require.Equal(t, newVersion.PrevVersion, *savedNewVersion.PrevVersion)
			require.Equal(t, newVersion.AddedFiles, savedNewVersion.AddedFiles)
			require.Equal(t, newVersion.RemovedFiles, savedNewVersion.RemovedFiles)
			require.Equal(t, newVersion.ModifiedFiles, savedNewVersion.ModifiedFiles)
			require.Equal(t, newVersion.CompanyID, savedNewVersion.CompanyID)
			require.Equal(t, companyID, savedNewVersion.CompanyID)
		})
	})
}
