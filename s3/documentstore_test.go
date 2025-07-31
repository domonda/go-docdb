package s3

import (
	"bytes"
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
	"github.com/stretchr/testify/require"
	"github.com/ungerik/go-fs"
)

func TestDocumentExists(t *testing.T) {
	client := fixtureS3Client(t)
	documentStore := FixtureDocumentStore(t)

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
				_, bucketName = FixtureCleanBucket(t, client)
			}
			documentID := uu.IDFrom("25a3eabf-6676-4c44-ae8a-a8007d0f6f1a")
			filename := "doc.pdf"
			createDocument := FixtureCreateDocument(t, client, bucketName)
			data := []byte("data")

			if scenario.bucketExists && scenario.documentExists {
				createDocument(documentID, filename, data)
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
	client := fixtureS3Client(t)
	documentStore := FixtureDocumentStore(t)

	t.Run("Iterates over fetched keys", func(t *testing.T) {
		// given
		timeout := time.AfterFunc(10*time.Second, func() {
			panic("TIMEOUT")
		})

		t.Cleanup(func() { timeout.Stop() })

		_, bucketName := FixtureCleanBucket(t, client)
		createDocument := FixtureCreateDocument(t, client, bucketName)

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
		_, bucketName := FixtureCleanBucket(t, client)
		filename := "doc.pdf"
		docID := uu.IDFrom("637c3457-f243-4ae6-b3b0-4182654832bc")
		createDocument := FixtureCreateDocument(t, client, bucketName)
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
		err := documentStore.EnumDocumentIDs(t.Context(), func(ctx context.Context, i uu.ID) error {
			return nil
		})

		// then
		require.Error(t, err)
	})
}

func TestCreateDocument(t *testing.T) {
	client := fixtureS3Client(t)
	documentStore := FixtureDocumentStore(t)

	t.Run("Saves files", func(t *testing.T) {
		// given
		_, bucketName := FixtureCleanBucket(t, client)
		docID := uu.IDFrom("40224cda-26d3-4691-ad4a-97abc65230c1")

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
			key := getKey(docID, file.Name(), docdb.ContentHash(file.FileData))
			_, err = client.GetObject(t.Context(), &awss3.GetObjectInput{Bucket: &bucketName, Key: &key})
			require.NoError(t, err)
		}
	})

	t.Run("Returns error if bucket does not exist", func(t *testing.T) {
		// when
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
	client := fixtureS3Client(t)
	documentStore := FixtureDocumentStore(t)

	t.Run("Returns proper versions", func(t *testing.T) {
		// given
		_, bucketName := FixtureCleanBucket(t, client)
		docID1 := uu.IDFrom("531a747b-a814-47a9-90cb-0d59ce52df7e")
		docID2 := uu.IDFrom("14f8f36c-8778-4567-9c8d-b1b998cb525a")
		filename1 := "doc1.pdf"
		filename2 := "doc2.pdf"
		content1 := []byte("asd")
		content2 := []byte("asdasd")
		createDoc := FixtureCreateDocument(t, client, bucketName)
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
		require.True(t, true, file1Exists)

		file2Exists, err := fileProvider.HasFile(filename2)
		require.NoError(t, err)
		require.True(t, true, file2Exists)

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
}

func TestReadDocumentHashFile(t *testing.T) {
	client := fixtureS3Client(t)
	documentStore := FixtureDocumentStore(t)

	t.Run("Returns file contents", func(t *testing.T) {
		// given
		_, bucketName := FixtureCleanBucket(t, client)
		docID := uu.IDFrom("45afa44f-3b8a-4b54-99dd-28ca92bb17cd")
		filename := "doc1.pdf"
		content := []byte("asdasd")
		createDocument := FixtureCreateDocument(t, client, bucketName)
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
		FixtureCleanBucket(t, client)
		docID := uu.IDFrom("24e4397c-c3bf-4e55-b993-ebef77107f17")
		filename := "doc1.pdf"

		// when
		_, err := documentStore.ReadDocumentHashFile(t.Context(), docID, filename, "hash")

		// then
		require.Error(t, err)
	})
}

func TestDeleteDocument(t *testing.T) {
	client := fixtureS3Client(t)
	documentStore := FixtureDocumentStore(t)

	t.Run("Deletes all objects belonging to a document", func(t *testing.T) {
		// given
		_, bucketName := FixtureCleanBucket(t, client)
		createDocument := FixtureCreateDocument(t, client, bucketName)
		docID1 := uu.IDFrom("c44677a0-d835-4ca5-9e27-4356296f94b2")
		docID2 := uu.IDFrom("b1c3b01f-7c5b-45e4-b5c4-b5c10e38c43a")
		filename1 := "doc1.pdf"
		filename2 := "doc2.pdf"
		content := []byte("asd")
		hash := docdb.ContentHash(content)
		createDocument(docID1, filename1, []byte("asd"))
		createDocument(docID1, filename2, []byte("asd"))
		createDocument(docID2, filename1, []byte("asd")) // shouldn't be deleted
		exists := FixtureObjectExists(t, client, bucketName)

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
		err := documentStore.DeleteDocument(t.Context(), uu.IDFrom("f8075810-a28a-47da-be72-05f0023b3112"))

		// then
		require.Error(t, err)
	})
}

func TestDeleteDocumentVersion(t *testing.T) {
	client := fixtureS3Client(t)
	documentStore := FixtureDocumentStore(t)

	t.Run("Deletes all objects belonging to a document version", func(t *testing.T) {
		// given
		_, bucketName := FixtureCleanBucket(t, client)
		createDocument := FixtureCreateDocument(t, client, bucketName)
		docID1 := uu.IDFrom("10a93961-cf1a-4352-bca2-49c8d46dbdd1")
		docID2 := uu.IDFrom("cd1d5e85-08fa-4408-9a2f-a4c6013a7dad")
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
		exists := FixtureObjectExists(t, client, bucketName)

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
		err := documentStore.DeleteDocumentHashes(
			t.Context(),
			uu.IDFrom("6920916f-8684-4d7e-9114-7b7409b2d279"),
			[]string{"asd"},
		)

		// then
		require.Error(t, err)
	})
}

func FixtureObjectExists(t *testing.T, client *awss3.Client, bucketName string) func(docID uu.ID, filename, hash string) bool {
	return func(docID uu.ID, filename, hash string) bool {
		_, err := client.GetObject(
			t.Context(),
			&awss3.GetObjectInput{
				Bucket: &bucketName,
				Key:    p(getKey(docID, filename, hash)),
			},
		)

		return err == nil
	}
}

func FixtureCleanBucket(t *testing.T, client *awss3.Client) (bucket *awss3.CreateBucketOutput, bucketName string) {
	t.Helper()
	bucketName = os.Getenv("BUCKET_NAME")

	createBucket := func() (*awss3.CreateBucketOutput, error) {
		return client.CreateBucket(t.Context(), &awss3.CreateBucketInput{
			Bucket: &bucketName,
			CreateBucketConfiguration: &types.CreateBucketConfiguration{
				LocationConstraint: types.BucketLocationConstraint(os.Getenv("AWS_DEFAULT_REGION")),
			},
		})
	}

	deleteBucket := func() error {
		// need to use background context, otherwise context is being canceled too early
		resp, err := client.ListObjectsV2(context.Background(), &awss3.ListObjectsV2Input{Bucket: &bucketName})
		if err != nil {
			t.Fatalf("Failed to list objects in bucket, %v", err)
		}

		if len(resp.Contents) > 0 {
			objectsToDelete := []types.ObjectIdentifier{}
			for _, obj := range resp.Contents {
				objectsToDelete = append(objectsToDelete, types.ObjectIdentifier{Key: obj.Key})
			}

			_, err = client.DeleteObjects(context.Background(), &awss3.DeleteObjectsInput{
				Bucket: p(bucketName),
				Delete: &types.Delete{
					Objects: objectsToDelete,
				},
			})

			if err != nil {
				t.Fatalf("Failed to delete objects, %v", err)
			}
		}

		_, err = client.DeleteBucket(context.Background(), &awss3.DeleteBucketInput{Bucket: &bucketName})
		return err
	}

	bucket, err := createBucket()

	if err != nil && strings.Contains(err.Error(), "BucketAlreadyOwnedByYou") {
		err = deleteBucket()
		if err != nil {
			t.Fatalf("Unable to delete existing bucket, %v", err)
		}

		bucket, err = createBucket()
		if err != nil {
			t.Fatalf("Unable to create bucket, %v", err)
		}
	}

	if err != nil {
		t.Fatalf("Unable to create bucket, %v", err)
	}

	t.Cleanup(func() { deleteBucket() })
	return bucket, bucketName
}

func FixtureDocumentStore(t *testing.T) docdb.DocumentStore {
	t.Helper()
	documentStore, err := NewS3DocumentStore(t.Context(), os.Getenv("BUCKET_NAME"))
	if err != nil {
		t.Fatal(err)
	}
	return documentStore
}

func fixtureS3Client(t *testing.T) *awss3.Client {
	t.Helper()
	cfg, err := config.LoadDefaultConfig(t.Context())
	if err != nil {
		t.Fatalf("Unable to load AWS SDK config, %v", err)
	}

	client := awss3.NewFromConfig(cfg)
	return client
}

func FixtureCreateDocument(
	t *testing.T,
	client *awss3.Client,
	bucketName string,
) func(
	docID uu.ID,
	filename string,
	content []byte,
) {

	return func(docID uu.ID, filename string, content []byte) {
		t.Helper()
		hash := docdb.ContentHash(content)
		_, err := client.PutObject(
			t.Context(),
			&awss3.PutObjectInput{
				Bucket: p(bucketName),
				Key:    p(getKey(docID, filename, hash)),
				Body:   bytes.NewReader(content),
			},
		)

		if err != nil {
			t.Fatalf("Falied to put object in S3, %v", err)
		}
	}
}
