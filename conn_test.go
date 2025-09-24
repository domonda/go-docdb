package docdb_test

import (
	"context"
	"testing"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/postgres"
	"github.com/domonda/go-docdb/postgres/pgfixtures"
	"github.com/domonda/go-docdb/s3"
	"github.com/domonda/go-docdb/s3/s3fixtures"
	"github.com/domonda/go-types/uu"
	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"
)

func TestConn(t *testing.T) {
	t.Run("Test AddDocumentVersion with postgres and S3", func(t *testing.T) {
		t.Run("Saves document version into postgres and S3", func(t *testing.T) {
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

			createVersion := func(
				ctx context.Context,
				prevVersion docdb.VersionTime,
				prevFiles docdb.FileProvider) (
				writeFiles []fs.FileReader,
				removeFiles []string,
				newCompanyID *uu.ID,
				err error,
			) {
				return nil, nil, nil, nil
			}

			onNewVersion := func(ctx context.Context, versionInfo *docdb.VersionInfo) error { return nil }

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
			// TODO
			// ????
			// Erik please help here

		})
	})
}
