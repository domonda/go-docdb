package docdb_test

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
			bucketName := s3fixtures.FixtureCleanBucket.Value(t)
			documentStore, err := s3.NewS3DocumentStore(bucketName)
			require.NoError(t, err)
			conn := docdb.NewConn(
				documentStore,
				postgres.NewMetadataStore(),
			)
			populator := pgfixtures.FixturePopulator.Value(t)
			documentVersionFile := populator.DocumentVersionFile()

			userID := uu.IDv7()

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

			ctx := pgfixtures.FixtureCtxWithTestTx.Value(t)

			// when
			err = conn.AddDocumentVersion(
				ctx,
				documentVersionFile.DocumentVersion.DocumentID,
				userID,
				"reason",
				createVersion,
				onNewVersion,
			)

			// then
			require.NoError(t, err)
			require.Equal(t, 1, len(newVersion.AddedFiles))
			require.Equal(t, 0, len(newVersion.RemovedFiles))
			require.Equal(t, 0, len(newVersion.ModifiedFiles))

			objectExists := s3fixtures.FixtureObjextExists.Value(t)
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
	})
}
