package s3_test

import (
	"bytes"
	"context"
	"errors"
	"testing"
	"time"

	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/s3"
	"github.com/domonda/go-docdb/s3/s3fixtures"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-types/uu"
	"github.com/stretchr/testify/require"
)

func TestDocumentExists(t *testing.T) {
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
			documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)

			bucketName := s3fixtures.FixtureNoBucket.Value(t)
			if scenario.bucketExists {
				bucketName = s3fixtures.FixtureCleanBucket.Value(t)
			}
			documentID := uu.IDv7()
			filename := "doc.pdf"

			createDocument := func(docID uu.ID, filename string, content []byte) error {
				hash := docdb.ContentHash(content)
				_, err := s3fixtures.FixtureGlobalS3Client.Value(t).PutObject(
					t.Context(),
					&awss3.PutObjectInput{
						Bucket: p(bucketName),
						Key:    p(s3.Key(docID, filename, hash)),
						Body:   bytes.NewReader(content),
					},
				)

				return err
			}
			data := []byte("data")

			if scenario.bucketExists && scenario.documentExists {
				err := createDocument(documentID, filename, data)
				require.NoError(t, err)
			}

			// when
			exists, err := documentStore.DocumentExists(t.Context(), documentID)

			// then
			scenario.compareError(t, err)
			scenario.compareResult(t, exists)
		})
	}
}

func TestEnumDocumentIDs(t *testing.T) {

	t.Run("Iterates over fetched keys", func(t *testing.T) {
		// given
		timeout := time.AfterFunc(10*time.Second, func() {
			panic("TIMEOUT")
		})

		t.Cleanup(func() { timeout.Stop() })

		createDocument := s3fixtures.FixtureCreateDocument.Value(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)

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
		err := documentStore.EnumDocumentIDs(t.Context(), func(ctx context.Context, i uu.ID) error {
			returnedIDs = append(returnedIDs, i)
			return nil
		})

		// then
		require.NoError(t, err)
		require.Equal(t, numDocuments, len(returnedIDs))
	})

	t.Run("Returns error from callback", func(t *testing.T) {
		// given
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)
		filename := "doc.pdf"
		docID := uu.IDv7()
		createDocument := s3fixtures.FixtureCreateDocument.Value(t)
		createDocument(docID, filename, []byte("asd"))

		// when
		expectedErr := errors.New("bug")
		err := documentStore.EnumDocumentIDs(t.Context(), func(ctx context.Context, i uu.ID) error {
			return expectedErr
		})

		// then
		require.ErrorIs(t, err, expectedErr)
	})

	t.Run("Returns error if bucket does not exist", func(t *testing.T) {
		// when
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)

		err := documentStore.EnumDocumentIDs(t.Context(), func(ctx context.Context, i uu.ID) error {
			return nil
		})

		// then
		require.Error(t, err)
	})
}

func TestCreateDocument(t *testing.T) {

	t.Run("Saves files", func(t *testing.T) {
		// given
		bucketName := s3fixtures.FixtureCleanBucket.Value(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)
		client := s3fixtures.FixtureGlobalS3Client.Value(t)
		docID := uu.IDv7()

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
		err := documentStore.CreateDocument(
			t.Context(),
			docID,
			[]fs.FileReader{files[0], files[1]},
		)

		// then
		require.NoError(t, err)

		for _, file := range files {
			key := s3.Key(docID, file.Name(), docdb.ContentHash(file.FileData))
			_, err = client.GetObject(t.Context(), &awss3.GetObjectInput{Bucket: &bucketName, Key: &key})
			require.NoError(t, err)
		}
	})

	t.Run("Returns error if bucket does not exist", func(t *testing.T) {
		// when
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)
		err := documentStore.CreateDocument(
			t.Context(),
			uu.IDv4(),
			[]fs.FileReader{&fs.MemFile{}},
		)

		// then
		require.Error(t, err)
	})
}

func TestDocumentHashFileProvider(t *testing.T) {
	t.Run("Returns proper versions", func(t *testing.T) {
		// given
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)
		docID1 := uu.IDv7()
		docID2 := uu.IDv7()
		filename1 := "doc1.pdf"
		filename2 := "doc2.pdf"
		content1 := []byte("asd")
		content2 := []byte("asdasd")
		createDoc := s3fixtures.FixtureCreateDocument.Value(t)
		createDoc(docID1, filename1, content1) // expected
		createDoc(docID1, filename2, content2) // expected
		createDoc(docID2, filename1, content1)
		hashes := []string{
			docdb.ContentHash(content1),
			docdb.ContentHash(content2),
		}

		// when
		fileProvider, err := documentStore.DocumentHashFileProvider(t.Context(), docID1, hashes)

		// then
		require.NoError(t, err)

		file1Exists, err := fileProvider.HasFile(filename1)
		require.NoError(t, err)
		require.True(t, file1Exists)

		file2Exists, err := fileProvider.HasFile(filename2)
		require.NoError(t, err)
		require.True(t, file2Exists)

		filenames, err := fileProvider.ListFiles(t.Context())
		require.NoError(t, err)
		require.Equal(t, []string{filename1, filename2}, filenames)

		savedContent1, err := fileProvider.ReadFile(t.Context(), filename1)
		require.NoError(t, err)
		require.Equal(t, content1, savedContent1)

		savedContent2, err := fileProvider.ReadFile(t.Context(), filename2)
		require.NoError(t, err)
		require.Equal(t, content2, savedContent2)
	})

	t.Run("Empty provider when no hashes", func(t *testing.T) {
		// given
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)

		// when
		fileProvider, err := documentStore.DocumentHashFileProvider(t.Context(), uu.IDv7(), nil)

		// then
		require.NoError(t, err)

		fileExists, err := fileProvider.HasFile("a")
		require.NoError(t, err)
		require.False(t, fileExists)

		filenames, err := fileProvider.ListFiles(t.Context())
		require.NoError(t, err)
		require.Nil(t, filenames)

		_, err = fileProvider.ReadFile(t.Context(), "b")
		require.Error(t, err)
	})
}

func TestReadDocumentHashFile(t *testing.T) {
	t.Run("Returns file contents", func(t *testing.T) {
		// given
		docID := uu.IDv7()
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)
		filename := "doc1.pdf"
		content := []byte("asdasd")
		createDocument := s3fixtures.FixtureCreateDocument.Value(t)
		createDocument(docID, filename, content)
		hash := docdb.ContentHash(content)

		// when
		result, err := documentStore.ReadDocumentHashFile(t.Context(), docID, filename, hash)

		// then
		require.NoError(t, err)
		require.Equal(t, content, result)
	})

	t.Run("Returns error if file does not exists", func(t *testing.T) {
		// given
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)
		docID := uu.IDv7()
		filename := "doc1.pdf"

		// when
		_, err := documentStore.ReadDocumentHashFile(t.Context(), docID, filename, "hash")

		// then
		require.Error(t, err)
	})
}

func TestDeleteDocument(t *testing.T) {
	t.Run("Deletes all objects belonging to a document", func(t *testing.T) {
		// given
		createDocument := s3fixtures.FixtureCreateDocument.Value(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)
		docID1 := uu.IDv7()
		docID2 := uu.IDv7()
		filename1 := "doc1.pdf"
		filename2 := "doc2.pdf"
		content := []byte("asd")
		hash := docdb.ContentHash(content)
		createDocument(docID1, filename1, []byte("asd"))
		createDocument(docID1, filename2, []byte("asd"))
		createDocument(docID2, filename1, []byte("asd")) // shouldn't be deleted
		exists := s3fixtures.FixtureObjextExists.Value(t)

		// when
		err := documentStore.DeleteDocument(t.Context(), docID1)

		// then
		require.NoError(t, err)
		require.False(t, exists(docID1, filename1, hash))
		require.False(t, exists(docID1, filename2, hash))
		require.True(t, exists(docID2, filename1, hash))
	})

	t.Run("Returns error if bucket does not exist", func(t *testing.T) {
		// when
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)
		err := documentStore.DeleteDocument(t.Context(), uu.IDFrom("f8075810-a28a-47da-be72-05f0023b3112"))

		// then
		require.Error(t, err)
	})
}

func TestDeleteDocumentVersion(t *testing.T) {
	t.Run("Deletes all objects belonging to a document version", func(t *testing.T) {
		// given
		createDocument := s3fixtures.FixtureCreateDocument.Value(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)
		docID1 := uu.IDv7()
		docID2 := uu.IDv7()
		filename1 := "doc1.pdf"
		filename2 := "doc2.pdf"
		content1 := []byte("asd1")
		content2 := []byte("asd2")
		content3 := []byte("asd3")
		content4 := []byte("asd4")
		hash1 := docdb.ContentHash(content1)
		hash2 := docdb.ContentHash(content2)
		hash3 := docdb.ContentHash(content3)
		hash4 := docdb.ContentHash(content4)
		createDocument(docID1, filename1, content1)
		createDocument(docID1, filename2, content2)
		createDocument(docID1, filename2, content3) // shouldn't be deleted
		createDocument(docID2, filename1, content4) // shouldn't be deleted
		exists := s3fixtures.FixtureObjextExists.Value(t)

		// when
		err := documentStore.DeleteDocumentHashes(t.Context(), docID1, []string{hash1, hash2})

		// then
		require.NoError(t, err)
		require.False(t, exists(docID1, filename1, hash1))
		require.False(t, exists(docID1, filename2, hash2))
		require.True(t, exists(docID1, filename2, hash3))
		require.True(t, exists(docID2, filename1, hash4))
	})

	t.Run("Returns error if bucket does not exist", func(t *testing.T) {
		// when
		documentStore := s3fixtures.FixtureGlobalDocumentStore.Value(t)
		err := documentStore.DeleteDocumentHashes(
			t.Context(),
			uu.IDFrom("6920916f-8684-4d7e-9114-7b7409b2d279"),
			[]string{"asd"},
		)

		// then
		require.Error(t, err)
	})
}

func p[T any](v T) *T { return &v }
