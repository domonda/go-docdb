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
	"github.com/domonda/go-types/uu"
	"github.com/stretchr/testify/require"
)

func TestDocumentExists(t *testing.T) {
	client := s3Client(t.Context(), t)
	conn, err := NewConn(t.Context(), os.Getenv("BUCKET_NAME"))

	if err != nil {
		t.Fatal(err)
	}

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
				_, bucketName = cleanBucket(t, client)
			}
			documentID := uu.IDFrom("25a3eabf-6676-4c44-ae8a-a8007d0f6f1a")
			documentData := bytes.NewReader([]byte("data"))

			if scenario.bucketExists && scenario.documentExists {
				_, err := client.PutObject(
					t.Context(),
					&awss3.PutObjectInput{
						Bucket: &bucketName,
						Key:    p(documentID.String()),
						Body:   documentData,
					},
				)
				if err != nil {
					t.Fatal(err)
				}
			}

			// when
			exists, err := conn.DocumentExists(t.Context(), documentID)

			// then
			scenario.compareError(t, err)
			scenario.compareResult(t, exists)
		})
	}
}

func TestEnumDocumentIDs(t *testing.T) {
	client := s3Client(t.Context(), t)
	conn, err := NewConn(t.Context(), os.Getenv("BUCKET_NAME"))
	if err != nil {
		t.Fatal(err)
	}

	t.Run("Iterates over fetched keys", func(t *testing.T) {
		// given
		timeout := time.AfterFunc(10*time.Second, func() {
			panic("TIMEOUT")
		})

		t.Cleanup(func() { timeout.Stop() })

		_, bucketName := cleanBucket(t, client)
		// uploader := manager.NewUploader(client)

		// max keys = 1000, this ensures pagination works correctly
		numDocuments := 1001
		for range numDocuments {
			id := uu.IDv4()
			_, err := client.PutObject(
				context.Background(),
				&awss3.PutObjectInput{
					Bucket: &bucketName,
					Key:    p(id.String()),
					Body:   bytes.NewReader([]byte("asd")),
				},
			)
			if err != nil {
				panic(err)
			}
		}

		// when
		returnedIDs := uu.IDSlice{}
		err = conn.EnumDocumentIDs(t.Context(), func(ctx context.Context, i uu.ID) error {
			returnedIDs = append(returnedIDs, i)
			return nil
		})

		// then
		require.NoError(t, err)
		require.Equal(t, numDocuments, len(returnedIDs))
	})

	t.Run("Returns error from callback", func(t *testing.T) {
		// given
		_, bucketName := cleanBucket(t, client)
		_, err := client.PutObject(
			t.Context(),
			&awss3.PutObjectInput{
				Bucket: &bucketName,
				Key:    p(uu.IDFrom("637c3457-f243-4ae6-b3b0-4182654832bc").String()),
				Body:   bytes.NewReader([]byte("asd")),
			},
		)
		if err != nil {
			t.Fatal(err)
		}

		// when
		expectedErr := errors.New("bug")
		err = conn.EnumDocumentIDs(t.Context(), func(ctx context.Context, i uu.ID) error {
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
}

func cleanBucket(t *testing.T, client *awss3.Client) (bucket *awss3.CreateBucketOutput, bucketName string) {
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

func s3Client(ctx context.Context, t *testing.T) *awss3.Client {
	t.Helper()
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		t.Fatalf("Unable to load AWS SDK config, %v", err)
	}

	client := awss3.NewFromConfig(cfg)
	return client
}
