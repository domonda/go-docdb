// Provides test fixtures for the s3 package

package s3fixtures

import (
	"bytes"
	"context"
	"os"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/datek/fix"
	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/s3"
	"github.com/domonda/go-types/uu"
)

var FixtureCreateDocument = fix.New(func(t *testing.T) func(
	docID uu.ID,
	filename string,
	content []byte,
) {
	client := FixtureGlobalS3Client.Value(t)
	bucketName := FixtureCleanBucket.Value(t)

	return func(docID uu.ID, filename string, content []byte) {
		hash := docdb.ContentHash(content)
		_, err := client.PutObject(
			t.Context(),
			&awss3.PutObjectInput{
				Bucket: p(bucketName),
				Key:    p(s3.Key(docID, filename, hash)),
				Body:   bytes.NewReader(content),
			},
		)

		if err != nil {
			t.Fatalf("Falied to put object in S3, %v", err)
		}
	}
})

var FixtureObjextExists = fix.New(func(t *testing.T) func(docID uu.ID, filename, hash string) bool {
	bucketName := FixtureCleanBucket.Value(t)
	client := FixtureGlobalS3Client.Value(t)

	return func(docID uu.ID, filename, hash string) bool {
		_, err := client.GetObject(
			t.Context(),
			&awss3.GetObjectInput{
				Bucket: &bucketName,
				Key:    p(s3.Key(docID, filename, hash)),
			},
		)

		return err == nil
	}
})

var FixtureNoBucket = fix.New(func(t *testing.T) string {
	bucketName := FixtureBucketName.Value(t)
	if err := deleteBucket(t.Context(), FixtureGlobalS3Client.Value(t), p(bucketName)); err != nil {
		t.Fatalf("Failed to delete bucket %s, %v", bucketName, err)
	}

	return bucketName
})

var FixtureCleanBucket = fix.New(func(t *testing.T) string {
	bucketName := FixtureBucketName.Value(t)
	client := FixtureGlobalS3Client.Value(t)
	createBucket := func() (*awss3.CreateBucketOutput, error) {
		return client.CreateBucket(t.Context(), &awss3.CreateBucketInput{
			Bucket: &bucketName,
			CreateBucketConfiguration: &types.CreateBucketConfiguration{
				LocationConstraint: types.BucketLocationConstraint(os.Getenv("AWS_DEFAULT_REGION")),
			},
		})
	}

	_, err := createBucket()

	if err != nil && strings.Contains(err.Error(), "BucketAlreadyOwnedByYou") {
		err = deleteBucket(t.Context(), client, p(bucketName))
		if err != nil {
			t.Fatalf("Unable to delete existing bucket, %v", err)
		}

		_, err = createBucket()
		if err != nil {
			t.Fatalf("Unable to create bucket, %v", err)
		}
	}

	if err != nil {
		t.Fatalf("Unable to create bucket, %v", err)
	}

	t.Cleanup(func() { deleteBucket(context.Background(), client, p(bucketName)) })
	return bucketName

})

var docStore docdb.DocumentStore

var FixtureGlobalDocumentStore = fix.New(func(t *testing.T) docdb.DocumentStore {
	if docStore != nil {
		return docStore
	}

	documentStore, err := s3.NewS3DocumentStore(FixtureBucketName.Value(t))
	if err != nil {
		t.Fatalf("Failed to create document store, %v", err)
	}

	docStore = documentStore
	return docStore
})

var s3Client *awss3.Client

var FixtureGlobalS3Client = fix.New(func(t *testing.T) *awss3.Client {
	if s3Client != nil {
		return s3Client
	}

	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		t.Fatalf("Unable to load AWS SDK config, %v", err)
	}

	s3Client = awss3.NewFromConfig(cfg)
	return s3Client
})

var FixtureBucketName = fix.New(func(t *testing.T) string {
	return os.Getenv("DOCDB_BUCKET_NAME")
})

func p[T any](v T) *T { return &v }

func deleteBucket(ctx context.Context, client *awss3.Client, bucketName *string) error {
	resp, err := client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{Bucket: bucketName})
	if err != nil && strings.Contains(err.Error(), "NoSuchBucket") {
		return nil
	}

	if err != nil {
		return err
	}

	if len(resp.Contents) > 0 {
		objectsToDelete := []types.ObjectIdentifier{}
		for _, obj := range resp.Contents {
			objectsToDelete = append(objectsToDelete, types.ObjectIdentifier{Key: obj.Key})
		}

		_, err = client.DeleteObjects(ctx, &awss3.DeleteObjectsInput{
			Bucket: bucketName,
			Delete: &types.Delete{
				Objects: objectsToDelete,
			},
		})
		if err != nil && !strings.Contains(err.Error(), "NoSuchBucket") {
			return err
		}
	}

	_, err = client.DeleteBucket(ctx, &awss3.DeleteBucketInput{Bucket: bucketName})
	if err != nil && !strings.Contains(err.Error(), "NoSuchBucket") {
		return err
	}
	return nil
}
