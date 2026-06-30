package s3store_test

import (
	"bytes"
	"fmt"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/storeconn/s3store"
	"github.com/domonda/go-docdb/storeconn/s3store/s3fixtures"
	"github.com/domonda/go-types/uu"
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
			documentStore := s3fixtures.FixtureGlobalDocumentStore(t)

			bucketName := s3fixtures.FixtureNoBucket(t)
			if scenario.bucketExists {
				bucketName = s3fixtures.FixtureCleanBucket(t)
			}
			documentID := uu.IDv7()
			filename := "doc.pdf"

			createDocument := func(docID uu.ID, filename string, content []byte) error {
				hash := docdb.ContentHash(content)
				_, err := s3fixtures.FixtureGlobalS3Client(t).PutObject(
					t.Context(),
					&awss3.PutObjectInput{
						Bucket: new(bucketName),
						Key:    new(s3store.Key(docID, filename, hash)),
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

func TestCreateDocumentVersion(t *testing.T) {
	t.Run("Saves files", func(t *testing.T) {
		// given
		bucketName := s3fixtures.FixtureCleanBucket(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		client := s3fixtures.FixtureGlobalS3Client(t)
		docID := uu.IDv7()
		version := docdb.NewVersionTime()

		files := []fs.MemFile{
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
		fileInfos, err := documentStore.CreateDocumentVersion(
			t.Context(),
			docID,
			version,
			[]fs.FileReader{files[0], files[1]},
		)

		// then
		require.NoError(t, err)

		// the returned FileInfos describe each stored file in input order
		require.Len(t, fileInfos, len(files))
		for i := range files {
			require.Equal(t, files[i].Name(), fileInfos[i].Name)
			require.Equal(t, files[i].Size(), fileInfos[i].Size)
			require.Equal(t, docdb.ContentHash(files[i].FileData), fileInfos[i].Hash)
		}

		for _, file := range files {
			key := s3store.Key(docID, file.Name(), docdb.ContentHash(file.FileData))
			_, err = client.GetObject(t.Context(), &awss3.GetObjectInput{Bucket: &bucketName, Key: &key})
			require.NoError(t, err)
		}
	})

	t.Run("Returns error if bucket does not exist", func(t *testing.T) {
		// when
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		_, err := documentStore.CreateDocumentVersion(
			t.Context(),
			uu.IDv4(),
			docdb.NewVersionTime(),
			[]fs.FileReader{&fs.MemFile{}},
		)

		// then
		require.Error(t, err)
	})
}

func TestDocumentHashFileProvider(t *testing.T) {
	t.Run("Returns proper versions", func(t *testing.T) {
		// given
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		docID1 := uu.IDv7()
		docID2 := uu.IDv7()
		filename1 := "doc1.pdf"
		filename2 := "doc2.pdf"
		content1 := []byte("asd")
		content2 := []byte("asdasd")
		createDoc := s3fixtures.FixtureCreateDocument(t)
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

		_, err = fileProvider.ReadFile(t.Context(), "imaginary file")
		require.ErrorIs(t, err, docdb.NewErrDocumentFileNotFound(docID1, "imaginary file"))
	})

	t.Run("Returns all files of a version with more than 1000 files", func(t *testing.T) {
		// given
		createDocument := s3fixtures.FixtureCreateDocument(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		docID := uu.IDv7()
		content := []byte("content")
		hash := docdb.ContentHash(content)
		const numObjects = 1001 // one more than the S3 list page size of 1000
		want := make([]string, numObjects)
		for i := range numObjects {
			// Same content (one hash) under distinct filenames yields distinct
			// keys, so the single hash matches all numObjects objects. The count
			// must stay above 1000 to force multi-page listing; the pre-fix code
			// capped at a single 1000-object List and silently dropped the rest.
			name := fmt.Sprintf("doc%04d.pdf", i)
			createDocument(docID, name, content)
			want[i] = name
		}

		// when
		fileProvider, err := documentStore.DocumentHashFileProvider(t.Context(), docID, []string{hash})

		// then
		require.NoError(t, err)
		filenames, err := fileProvider.ListFiles(t.Context())
		require.NoError(t, err)
		require.ElementsMatch(t, want, filenames, "all >1000 matching files must be returned, proving the 1000-object cap is gone")
	})

	t.Run("Empty provider when no hashes", func(t *testing.T) {
		// given
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		docID := uu.IDv7()

		// when
		fileProvider, err := documentStore.DocumentHashFileProvider(t.Context(), docID, nil)

		// then
		require.NoError(t, err)

		fileExists, err := fileProvider.HasFile("a")
		require.NoError(t, err)
		require.False(t, fileExists)

		filenames, err := fileProvider.ListFiles(t.Context())
		require.NoError(t, err)
		require.Nil(t, filenames)

		_, err = fileProvider.ReadFile(t.Context(), "b")
		require.ErrorIs(t, err, docdb.NewErrDocumentFileNotFound(docID, "b"))
	})
}

func TestReadDocumentHashFile(t *testing.T) {
	t.Run("Returns file contents", func(t *testing.T) {
		// given
		docID := uu.IDv7()
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		filename := "doc1.pdf"
		content := []byte("asdasd")
		createDocument := s3fixtures.FixtureCreateDocument(t)
		createDocument(docID, filename, content)
		hash := docdb.ContentHash(content)

		// when
		result, err := documentStore.ReadDocumentHashFile(t.Context(), docID, filename, hash)

		// then
		require.NoError(t, err)
		require.Equal(t, content, result)
	})

	t.Run("Returns ErrDocumentFileNotFound if file does not exist", func(t *testing.T) {
		// given
		s3fixtures.FixtureCleanBucket(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		docID := uu.IDv7()
		filename := "doc1.pdf"

		// when
		_, err := documentStore.ReadDocumentHashFile(t.Context(), docID, filename, "hash")

		// then
		require.ErrorIs(t, err, docdb.NewErrDocumentFileNotFound(docID, filename))
	})
}

func TestDeleteDocument(t *testing.T) {
	t.Run("Deletes all objects belonging to a document", func(t *testing.T) {
		// given
		createDocument := s3fixtures.FixtureCreateDocument(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		docID1 := uu.IDv7()
		docID2 := uu.IDv7()
		filename1 := "doc1.pdf"
		filename2 := "doc2.pdf"
		content := []byte("asd")
		hash := docdb.ContentHash(content)
		createDocument(docID1, filename1, []byte("asd"))
		createDocument(docID1, filename2, []byte("asd"))
		createDocument(docID2, filename1, []byte("asd")) // shouldn't be deleted
		exists := s3fixtures.FixtureObjectExists(t)

		// when
		err := documentStore.DeleteDocument(t.Context(), docID1)

		// then
		require.NoError(t, err)
		require.False(t, exists(docID1, filename1, hash))
		require.False(t, exists(docID1, filename2, hash))
		require.True(t, exists(docID2, filename1, hash))
	})

	t.Run("Deletes all objects of a document with more than 1000 objects", func(t *testing.T) {
		// given
		createDocument := s3fixtures.FixtureCreateDocument(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		docID := uu.IDv7()
		otherID := uu.IDv7()
		const numObjects = 1001 // one more than the S3 list/delete page size of 1000
		// Each file shares the same content (and therefore the same content
		// hash) but has a unique filename, so the keys
		// "<docID>/doc0000.pdf/<hash>" … "<docID>/doc1000.pdf/<hash>" are all
		// distinct. The count must stay above 1000 to force multi-page listing
		// and batched deletion; collapsing the filenames to a constant would
		// silently reduce this to a single object and pass without exercising
		// the pagination path under test.
		for i := range numObjects {
			createDocument(docID, fmt.Sprintf("doc%04d.pdf", i), []byte("content"))
		}
		createDocument(otherID, "keep.pdf", []byte("content")) // shouldn't be deleted

		// when
		err := documentStore.DeleteDocument(t.Context(), docID)

		// then
		require.NoError(t, err)
		exists, err := documentStore.DocumentExists(t.Context(), docID)
		require.NoError(t, err)
		require.False(t, exists, "all objects of the document should be deleted")
		otherExists, err := documentStore.DocumentExists(t.Context(), otherID)
		require.NoError(t, err)
		require.True(t, otherExists, "other documents must not be affected")
	})

	t.Run("Returns ErrDocumentNotFound if document does not exist", func(t *testing.T) {
		// given
		s3fixtures.FixtureCleanBucket(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		docID := uu.IDv7()

		// when
		err := documentStore.DeleteDocument(t.Context(), docID)

		// then
		require.ErrorIs(t, err, docdb.NewErrDocumentNotFound(docID))
	})

	t.Run("Returns error if bucket does not exist", func(t *testing.T) {
		// when
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		err := documentStore.DeleteDocument(t.Context(), uu.IDFrom("f8075810-a28a-47da-be72-05f0023b3112"))

		// then
		require.Error(t, err)
	})
}

func TestDeleteDocumentHashes(t *testing.T) {
	t.Run("Deletes all objects belonging to a document version", func(t *testing.T) {
		// given
		createDocument := s3fixtures.FixtureCreateDocument(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
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
		exists := s3fixtures.FixtureObjectExists(t)

		// when
		err := documentStore.DeleteDocumentHashes(t.Context(), docID1, []string{hash1, hash2})

		// then
		require.NoError(t, err)
		require.False(t, exists(docID1, filename1, hash1))
		require.False(t, exists(docID1, filename2, hash2))
		require.True(t, exists(docID1, filename2, hash3))
		require.True(t, exists(docID2, filename1, hash4))
	})

	t.Run("Returns ErrDocumentNotFound if document does not exist", func(t *testing.T) {
		// given
		s3fixtures.FixtureCleanBucket(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		docID := uu.IDv7()

		// when
		err := documentStore.DeleteDocumentHashes(t.Context(), docID, []string{"asd"})

		// then
		require.ErrorIs(t, err, docdb.NewErrDocumentNotFound(docID))
	})

	t.Run("Returns error if bucket does not exist", func(t *testing.T) {
		// when
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		err := documentStore.DeleteDocumentHashes(
			t.Context(),
			uu.IDFrom("6920916f-8684-4d7e-9114-7b7409b2d279"),
			[]string{"asd"},
		)

		// then
		require.Error(t, err)
	})

	t.Run("Deletes all matching objects of a document with more than 1000 objects", func(t *testing.T) {
		// given
		createDocument := s3fixtures.FixtureCreateDocument(t)
		documentStore := s3fixtures.FixtureGlobalDocumentStore(t)
		docID := uu.IDv7()
		otherID := uu.IDv7()
		content := []byte("content")
		hash := docdb.ContentHash(content)
		const numObjects = 1001 // one more than the S3 list/delete page size of 1000
		for i := range numObjects {
			// Same content (one hash) under distinct filenames yields distinct
			// keys, so a single hash matches all numObjects objects to delete.
			createDocument(docID, fmt.Sprintf("doc%04d.pdf", i), content)
		}
		createDocument(otherID, "keep.pdf", content) // shouldn't be deleted

		// when
		err := documentStore.DeleteDocumentHashes(t.Context(), docID, []string{hash})

		// then
		require.NoError(t, err)
		exists, err := documentStore.DocumentExists(t.Context(), docID)
		require.NoError(t, err)
		require.False(t, exists, "all matching objects of the document should be deleted")
		otherExists, err := documentStore.DocumentExists(t.Context(), otherID)
		require.NoError(t, err)
		require.True(t, otherExists, "other documents must not be affected")
	})
}

// TestDeleteObjectsErr is a pure unit test (no S3 backend needed): S3 reports
// per-object delete failures inside an HTTP-200 DeleteObjects response via the
// Errors field rather than as a transport error, so DeleteObjectsErr must turn
// a non-empty Errors slice into an error and an empty one into nil.
func TestDeleteObjectsErr(t *testing.T) {
	t.Run("Returns nil when no per-object failures", func(t *testing.T) {
		require.NoError(t, s3store.DeleteObjectsErr(nil))
		require.NoError(t, s3store.DeleteObjectsErr(&awss3.DeleteObjectsOutput{}))
		require.NoError(t, s3store.DeleteObjectsErr(&awss3.DeleteObjectsOutput{
			Errors: []types.Error{},
		}))
	})

	t.Run("Returns error describing per-object failures", func(t *testing.T) {
		out := &awss3.DeleteObjectsOutput{
			Errors: []types.Error{
				{Key: aws.String("doc/file.pdf/hash"), Code: aws.String("AccessDenied"), Message: aws.String("nope")},
				{Key: aws.String("doc/other.pdf/hash"), Code: aws.String("InternalError"), Message: aws.String("boom")},
			},
		}
		err := s3store.DeleteObjectsErr(out)
		require.Error(t, err)
		// Reports the total count and identifies the first failing object so the
		// caller can act on it instead of silently leaving objects behind.
		require.Contains(t, err.Error(), "2 per-object failure")
		require.Contains(t, err.Error(), "doc/file.pdf/hash")
		require.Contains(t, err.Error(), "AccessDenied")
	})
}
