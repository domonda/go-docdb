package s3

import (
	"bytes"
	"context"
	"os"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
)

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
				Key:    p(Key(docID, filename, hash)),
				Body:   bytes.NewReader(content),
			},
		)

		if err != nil {
			t.Fatalf("Falied to put object in S3, %v", err)
		}
	}
}

func FixtureObjectExists(t *testing.T, client *awss3.Client, bucketName string) func(docID uu.ID, filename, hash string) bool {
	return func(docID uu.ID, filename, hash string) bool {
		_, err := client.GetObject(
			t.Context(),
			&awss3.GetObjectInput{
				Bucket: &bucketName,
				Key:    p(Key(docID, filename, hash)),
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

func FixtureS3Client(t *testing.T) *awss3.Client {
	t.Helper()
	cfg, err := config.LoadDefaultConfig(t.Context())
	if err != nil {
		t.Fatalf("Unable to load AWS SDK config, %v", err)
	}

	client := awss3.NewFromConfig(cfg)
	return client
}
