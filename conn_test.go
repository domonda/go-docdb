package docdb_test

import (
	"context"
	"errors"
	"io"
	"testing"
	"time"

	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/postgres"
	"github.com/domonda/go-docdb/s3"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/uu"
	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"
)

func TestS3WithPostgres(t *testing.T) {
	conn := fixtureS3PostgresConn(t)
	s3Client := s3.FixtureS3Client(t)
	t.Run("TestDocumentExists", func(t *testing.T) {

		scenarios := []struct {
			name           string
			bucketExists   bool
			documentExists bool
			compareResult  func(t require.TestingT, value bool, msgAndArgs ...any)
			compareError   func(t require.TestingT, err error, msgAndArgs ...any)
		}{
			{
				name:           "Returns true if document exists",
				bucketExists:   true,
				documentExists: true,
				compareResult:  require.True,
				compareError:   require.NoError,
			},
			{
				name:           "Returns false if document does not",
				bucketExists:   true,
				documentExists: false,
				compareResult:  require.False,
				compareError:   require.NoError,
			},
			{
				name:           "Returns error if bucket does not exist",
				bucketExists:   false,
				documentExists: false,
				compareResult:  require.False,
				compareError:   require.Error,
			},
		}
		for _, scenario := range scenarios {
			t.Run(scenario.name, func(t *testing.T) {
				// given
				bucketName := ""
				if scenario.bucketExists {
					_, bucketName = s3.FixtureCleanBucket(t, s3Client)
				}
				documentID := uu.IDFrom("25a3eabf-6676-4c44-ae8a-a8007d0f6f1a")
				filename := "doc.pdf"
				createDocument := s3.FixtureCreateDocument(t, s3Client, bucketName)
				data := []byte("data")

				if scenario.bucketExists && scenario.documentExists {
					createDocument(documentID, filename, data)
				}

				// when
				exists, err := conn.DocumentExists(t.Context(), documentID)

				// then
				scenario.compareError(t, err)
				scenario.compareResult(t, exists)
			})
		}
	})

	t.Run("TestEnumDocumentIDs", func(t *testing.T) {

		t.Run("Iterates over fetched keys", func(t *testing.T) {
			// given
			timeout := time.AfterFunc(10*time.Second, func() {
				panic("TIMEOUT")
			})

			t.Cleanup(func() { timeout.Stop() })

			_, bucketName := s3.FixtureCleanBucket(t, s3Client)
			createDocument := s3.FixtureCreateDocument(t, s3Client, bucketName)

			// max keys = 1000, this ensures pagination works correctly, because 501 * 2 = 1002
			numDocuments := 501
			for range numDocuments {
				id := uu.IDv4()

				for _, filename := range []string{"doc.pdf", "doc1.pdf"} {
					createDocument(id, filename, []byte("asd"))
				}
			}

			// when
			returnedIDs := uu.IDSlice{}
			err := conn.EnumDocumentIDs(t.Context(), func(ctx context.Context, i uu.ID) error {
				returnedIDs = append(returnedIDs, i)
				return nil
			})

			// then
			require.NoError(t, err)
			require.Equal(t, numDocuments, len(returnedIDs))
		})

		t.Run("Returns error from callback", func(t *testing.T) {
			// given
			_, bucketName := s3.FixtureCleanBucket(t, s3Client)
			filename := "doc.pdf"
			docID := uu.IDFrom("637c3457-f243-4ae6-b3b0-4182654832bc")
			createDocument := s3.FixtureCreateDocument(t, s3Client, bucketName)
			createDocument(docID, filename, []byte("asd"))

			// when
			expectedErr := errors.New("bug")
			err := conn.EnumDocumentIDs(t.Context(), func(ctx context.Context, i uu.ID) error {
				return expectedErr
			})

			// then
			require.ErrorIs(t, err, expectedErr)
		})

		t.Run("Returns error if bucket does not exist", func(t *testing.T) {
			// when
			err := conn.EnumDocumentIDs(t.Context(), func(ctx context.Context, i uu.ID) error {
				return nil
			})

			// then
			require.Error(t, err)
		})
	})

	t.Run("TestCreateDocument", func(t *testing.T) {
		t.Run("Saves files and metadata", func(t *testing.T) {
			// given
			_, bucketName := s3.FixtureCleanBucket(t, s3Client)
			companyID := uu.IDFrom("6c19674a-05c6-439e-965f-a9f43f1ecf3c")
			docID := uu.IDFrom("40224cda-26d3-4691-ad4a-97abc65230c1")
			userID := uu.IDFrom("6effbcb9-8e6f-4381-afac-90a62c54363f")
			reason := "whatever"

			files := []*fs.MemFile{
				{
					FileName: "a.pdf",
					FileData: []byte("a"),
				},
				{
					FileName: "b.json",
					FileData: []byte("b"),
				},
			}

			// when
			_, err := conn.CreateDocument(
				t.Context(),
				companyID,
				docID,
				userID,
				reason,
				[]fs.FileReader{files[0], files[1]},
			)

			// then
			require.NoError(t, err)

			// assert files contents
			for _, file := range files {
				key := s3.Key(docID, file.Name(), docdb.ContentHash(file.FileData))
				obj, err := s3Client.GetObject(t.Context(), &awss3.GetObjectInput{Bucket: &bucketName, Key: &key})
				require.NoError(t, err)
				data, err := io.ReadAll(obj.Body)
				require.NoError(t, err)
				require.Equal(t, file.FileData, data)
			}

			// assert metadata
			exists, err := db.QueryValue[bool](
				t.Context(),
				/*sql*/ `
				select(exists(
					select
					from public.document
					where id = $1
				))`,
				docID,
			)
			require.NoError(t, err)
			require.True(t, exists)
		})

		t.Run("Returns error if bucket does not exist", func(t *testing.T) {
			// when
			_, err := conn.CreateDocument(
				t.Context(),
				uu.IDv4(),
				uu.IDv4(),
				uu.IDv4(),
				"",
				[]fs.FileReader{&fs.MemFile{}},
			)

			// then
			require.Error(t, err)
		})
	})
}

func fixtureS3PostgresConn(t *testing.T) docdb.Conn {
	t.Helper()

	return docdb.NewConn(
		s3.FixtureDocumentStore(t),
		postgres.FixturePostgresMetadataStore(t),
	)
}
