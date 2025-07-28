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
	documentStore := fixtureDocumentStore(t)

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
				_, bucketName = fixtureCleanBucket(t, client)
			}
			documentID := uu.IDFrom("25a3eabf-6676-4c44-ae8a-a8007d0f6f1a")
			documentData := bytes.NewReader([]byte("data"))
			version := docdb.NewVersionTime(t.Context())
			filename := "doc.pdf"

			if scenario.bucketExists && scenario.documentExists {
				_, err := client.PutObject(
					t.Context(),
					&awss3.PutObjectInput{
						Bucket: &bucketName,
						Key:    p(getKey(documentID, version, filename)),
						Body:   documentData,
					},
				)
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
	client := fixtureS3Client(t)
	documentStore := fixtureDocumentStore(t)

	t.Run("Iterates over fetched keys", func(t *testing.T) {
		// given
		timeout := time.AfterFunc(10*time.Second, func() {
			panic("TIMEOUT")
		})

		t.Cleanup(func() { timeout.Stop() })

		_, bucketName := fixtureCleanBucket(t, client)

		// max keys = 1000, this ensures pagination works correctly, because 501 * 2 = 1002
		numDocuments := 501
		for range numDocuments {
			version := docdb.NewVersionTime(t.Context())
			id := uu.IDv4()

			for _, filename := range []string{"doc.pdf", "doc1.pdf"} {
				_, err := client.PutObject(
					context.Background(),
					&awss3.PutObjectInput{
						Bucket: &bucketName,
						Key:    p(getKey(id, version, filename)),
						Body:   bytes.NewReader([]byte("asd")),
					},
				)
				require.NoError(t, err)
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
		_, bucketName := fixtureCleanBucket(t, client)
		version := docdb.NewVersionTime(t.Context())
		filename := "doc.pdf"
		docID := uu.IDFrom("637c3457-f243-4ae6-b3b0-4182654832bc")

		_, err := client.PutObject(
			t.Context(),
			&awss3.PutObjectInput{
				Bucket: &bucketName,
				Key:    p(getKey(docID, version, filename)),
				Body:   bytes.NewReader([]byte("asd")),
			},
		)
		require.NoError(t, err)

		// when
		expectedErr := errors.New("bug")
		err = documentStore.EnumDocumentIDs(t.Context(), func(ctx context.Context, i uu.ID) error {
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
	documentStore := fixtureDocumentStore(t)

	t.Run("Saves files", func(t *testing.T) {
		// given
		_, bucketName := fixtureCleanBucket(t, client)
		version := docdb.NewVersionTime(t.Context())
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
			version,
			[]fs.FileReader{files[0], files[1]},
		)

		// then
		require.NoError(t, err)

		for _, file := range files {
			key := getKey(docID, version, file.FileName)
			_, err = client.GetObject(t.Context(), &awss3.GetObjectInput{Bucket: &bucketName, Key: &key})
			require.NoError(t, err)
		}
	})

	t.Run("Returns error if bucket does not exist", func(t *testing.T) {
		// when
		err := documentStore.CreateDocument(
			t.Context(),
			uu.IDv4(),
			docdb.NewVersionTime(t.Context()),
			[]fs.FileReader{&fs.MemFile{}},
		)

		// then
		require.Error(t, err)
	})
}

func TestDocumentVersionFileProvider(t *testing.T) {
	client := fixtureS3Client(t)
	documentStore := fixtureDocumentStore(t)

	t.Run("Returns proper versions", func(t *testing.T) {
		// given
		_, bucketName := fixtureCleanBucket(t, client)
		docID1 := uu.IDFrom("531a747b-a814-47a9-90cb-0d59ce52df7e")
		docID2 := uu.IDFrom("14f8f36c-8778-4567-9c8d-b1b998cb525a")
		filename1 := "doc1.pdf"
		filename2 := "doc2.pdf"
		filename3 := "doc3.pdf"
		filename4 := "doc4.pdf"
		filename5 := "doc4.pdf"
		version1 := docdb.NewVersionTime(t.Context())
		version2 := docdb.NewVersionTime(t.Context())
		version2.Time = time.Now().Add(1 * time.Second)
		content1 := []byte("asd")
		content2 := []byte("asdasd")

		require.NotEqual(t, version1, version2)

		createDoc := func(docID uu.ID, version docdb.VersionTime, filename string, content []byte) {
			_, err := client.PutObject(
				t.Context(),
				&awss3.PutObjectInput{
					Bucket: &bucketName,
					Key:    p(getKey(docID, version, filename)),
					Body:   bytes.NewReader(content),
				},
			)
			require.NoError(t, err)
		}

		createDoc(docID1, version1, filename1, content1) // expected
		createDoc(docID1, version1, filename2, content2) // expected
		createDoc(docID1, version2, filename3, content1)
		createDoc(docID1, version2, filename4, content1)
		createDoc(docID2, version1, filename5, content1)

		// when
		fileProvider, err := documentStore.DocumentVersionFileProvider(t.Context(), docID1, version1)

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

func TestReadDocumentVersionFile(t *testing.T) {
	client := fixtureS3Client(t)
	documentStore := fixtureDocumentStore(t)

	t.Run("Returns file contents", func(t *testing.T) {
		// given
		_, bucketName := fixtureCleanBucket(t, client)
		docID := uu.IDFrom("45afa44f-3b8a-4b54-99dd-28ca92bb17cd")
		filename := "doc1.pdf"
		version := docdb.NewVersionTime(t.Context())
		contents := []byte("asdasd")

		_, err := client.PutObject(
			t.Context(),
			&awss3.PutObjectInput{
				Bucket: p(bucketName),
				Key:    p(getKey(docID, version, filename)),
				Body:   bytes.NewReader(contents),
			},
		)
		require.NoError(t, err)

		// when
		result, err := documentStore.ReadDocumentVersionFile(t.Context(), docID, version, filename)

		// then
		require.NoError(t, err)
		require.Equal(t, contents, result)
	})

	t.Run("Returns error if file does not exists", func(t *testing.T) {
		// given
		fixtureCleanBucket(t, client)
		docID := uu.IDFrom("24e4397c-c3bf-4e55-b993-ebef77107f17")
		filename := "doc1.pdf"
		version := docdb.NewVersionTime(t.Context())

		// when
		_, err := documentStore.ReadDocumentVersionFile(t.Context(), docID, version, filename)

		// then
		require.Error(t, err)
	})
}

func fixtureCleanBucket(t *testing.T, client *awss3.Client) (bucket *awss3.CreateBucketOutput, bucketName string) {
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
		out, err := client.ListObjectsV2(context.Background(), &awss3.ListObjectsV2Input{Bucket: &bucketName})
		if err != nil {
			t.Fatalf("Failed to list objects in bucket, %v", err)
		}

		for _, item := range out.Contents {
			_, err = client.DeleteObject(context.Background(), &awss3.DeleteObjectInput{
				Bucket: &bucketName,
				Key:    item.Key,
			})

			if err != nil {
				t.Fatalf("Failed to delete object, %v", err)
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

func fixtureDocumentStore(t *testing.T) docdb.DocumentStore {
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
