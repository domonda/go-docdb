package integrationtests

import (
	"context"
	"testing"

	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/postgres"
	"github.com/domonda/go-docdb/postgres/pgfixtures"
	"github.com/domonda/go-docdb/s3"
	"github.com/domonda/go-docdb/s3/s3fixtures"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/uu"
)

func TestConn(t *testing.T) {
	t.Run("Test AddDocumentVersion with postgres and S3", func(t *testing.T) {
		t.Run("Adds new files to the new version", func(t *testing.T) {
			// given
			bucketName := s3fixtures.FixtureCleanBucket(t)
			documentStore := s3.NewS3DocumentStore(bucketName, s3fixtures.FixtureGlobalS3Client(t))
			conn := docdb.NewConn(
				documentStore,
				postgres.NewMetadataStore(),
			)
			populator := pgfixtures.FixturePopulator(t)
			documentVersionFile := populator.DocumentVersionFile()

			newFile := fs.NewMemFile("doc-a.pdf", []byte("a"))

			newVersion := &docdb.VersionInfo{}

			ctx := pgfixtures.FixtureCtxWithTestTx(t)

			// when
			err := conn.AddDocumentVersion(
				ctx,
				documentVersionFile.DocumentVersion.DocumentID,
				uu.IDv7(),
				"reason",
				func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
					return &docdb.CreateVersionResult{
						Version:    docdb.NewVersionTime(),
						WriteFiles: []fs.FileReader{newFile},
					}, nil
				},
				docdb.CaptureNewVersionInfo(&newVersion),
			)

			// then
			require.NoError(t, err)
			require.Equal(t, 1, len(newVersion.AddedFiles))
			require.Equal(t, 0, len(newVersion.RemovedFiles))
			require.Equal(t, 0, len(newVersion.ModifiedFiles))

			objectExists := s3fixtures.FixtureObjectExists(t)
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

			newVersion := &docdb.VersionInfo{}

			ctx := pgfixtures.FixtureCtxWithTestTx(t)

			// when
			err := conn.AddDocumentVersion(
				ctx,
				documentVersionFile.DocumentVersion.DocumentID,
				uu.IDv7(),
				"reason",
				func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
					return &docdb.CreateVersionResult{
						Version:    docdb.NewVersionTime(),
						WriteFiles: []fs.FileReader{modifiedFile},
					}, nil
				},
				docdb.CaptureNewVersionInfo(&newVersion),
			)

			// then
			require.NoError(t, err)
			require.Equal(t, 0, len(newVersion.AddedFiles))
			require.Equal(t, 0, len(newVersion.RemovedFiles))
			require.Equal(t, 1, len(newVersion.ModifiedFiles))

			objectExists := s3fixtures.FixtureObjectExists(t)
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

			newVersion := &docdb.VersionInfo{}

			ctx := pgfixtures.FixtureCtxWithTestTx(t)

			// when
			err := conn.AddDocumentVersion(
				ctx,
				documentVersionFile.DocumentVersion.DocumentID,
				uu.IDv7(),
				"reason",
				func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
					return &docdb.CreateVersionResult{
						Version:     docdb.NewVersionTime(),
						RemoveFiles: []string{documentVersionFile.Name},
					}, nil
				},
				docdb.CaptureNewVersionInfo(&newVersion),
			)

			// then
			require.NoError(t, err)
			require.Equal(t, 0, len(newVersion.AddedFiles))
			require.Equal(t, 1, len(newVersion.RemovedFiles))
			require.Equal(t, 0, len(newVersion.ModifiedFiles))
			objectExists := s3fixtures.FixtureObjectExists(t)
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
			newCompanyID := uu.IDv7()

			newVersion := &docdb.VersionInfo{}

			ctx := pgfixtures.FixtureCtxWithTestTx(t)

			// when
			err := conn.AddDocumentVersion(
				ctx,
				documentVersion.DocumentID,
				uu.IDv7(),
				"reason",
				func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
					return &docdb.CreateVersionResult{
						Version:      docdb.NewVersionTime(),
						NewCompanyID: uu.NullableID(newCompanyID),
					}, nil
				},
				docdb.CaptureNewVersionInfo(&newVersion),
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
			require.Equal(t, newCompanyID, savedNewVersion.CompanyID)
		})

		t.Run("Rolls back changes if onNewVersion panics", func(t *testing.T) {
			// given
			documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
			bucketName := s3fixtures.FixtureCleanBucket(t)
			conn := docdb.NewConn(
				documentStore,
				postgres.NewMetadataStore(),
			)
			populator := pgfixtures.FixturePopulator(t)
			documentVersion := populator.DocumentVersion()
			newCompanyID := uu.IDv7()

			ctx := pgfixtures.FixtureCtxWithTestTx(t)

			// when
			err := conn.AddDocumentVersion(
				ctx,
				documentVersion.DocumentID,
				uu.IDv7(), // userID
				"reason",
				func(ctx context.Context, prevVersion docdb.VersionTime, prevFiles docdb.FileProvider) (*docdb.CreateVersionResult, error) {
					return &docdb.CreateVersionResult{
						Version:      docdb.NewVersionTime(),
						WriteFiles:   []fs.FileReader{fs.NewMemFile("doc-a.pdf", []byte("a"))},
						NewCompanyID: uu.NullableID(newCompanyID),
					}, nil
				},
				func(ctx context.Context, versionInfo *docdb.VersionInfo) error {
					panic("bug")
				},
			)

			// then
			require.ErrorContains(t, err, "bug")
			versions, err := db.QueryValue[int](
				ctx,
				/* sql */ `
				select count(*) from docdb.document_version where document_id = $1`,
				documentVersion.DocumentID,
			)

			require.NoError(t, err)
			require.Equal(t, 1, versions)

			s3client := s3fixtures.FixtureGlobalS3Client(t)

			response, err := s3client.ListObjectsV2(
				ctx,
				&awss3.ListObjectsV2Input{
					Bucket: p(bucketName),
					Prefix: p(documentVersion.DocumentID.String() + "/"),
				},
			)

			require.Nil(t, err)
			require.Equal(t, 0, len(response.Contents))

		})
	})
}

func p[T any](v T) *T { return &v }
