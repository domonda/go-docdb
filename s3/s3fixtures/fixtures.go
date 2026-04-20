// Package s3fixtures provides shared test fixtures for the s3 package.
// Fixtures are built on github.com/datek/fix and are lazily initialized per
// test; clients come from AWS config and the following environment variables:
//
//	DOCDB_BUCKET_NAME    bucket used by the fixtures
//	AWS_DEFAULT_REGION   region used when creating buckets
//	AWS_ENDPOINT_URL     optional custom endpoint (e.g. LocalStack)
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

// FixtureCreateDocument returns a helper that writes a single document file
// to the fixture bucket under the canonical "<docID>/<filename>/<hash>" key,
// using the fixture S3 client. The helper calls t.Fatal on any error.
var FixtureCreateDocument = fix.New(func(t *testing.T) func(
	docID uu.ID,
	filename string,
	content []byte,
) {
	client := FixtureGlobalS3Client(t)
	bucketName := FixtureCleanBucket(t)

	return func(docID uu.ID, filename string, content []byte) {
		hash := docdb.ContentHash(content)
		_, err := client.PutObject(
			t.Context(),
			&awss3.PutObjectInput{
				Bucket: new(bucketName),
				Key:    new(s3.Key(docID, filename, hash)),
				Body:   bytes.NewReader(content),
			},
		)

		if err != nil {
			t.Fatalf("Failed to put object in S3, %v", err)
		}
	}
})

// FixtureObjectExists returns a helper that reports whether the object for
// the passed (docID, filename, hash) is present in the fixture bucket.
// A successful GetObject counts as "exists"; any error is treated as "not exists".
var FixtureObjectExists = fix.New(func(t *testing.T) func(docID uu.ID, filename, hash string) bool {
	bucketName := FixtureCleanBucket(t)
	client := FixtureGlobalS3Client(t)

	return func(docID uu.ID, filename, hash string) bool {
		_, err := client.GetObject(
			t.Context(),
			&awss3.GetObjectInput{
				Bucket: &bucketName,
				Key:    new(s3.Key(docID, filename, hash)),
			},
		)

		return err == nil
	}
})

// FixtureNoBucket ensures the fixture bucket does not exist by deleting it
// (and any contained objects) if present. Returns the bucket name for use
// in test assertions. Calls t.Fatal if deletion fails.
var FixtureNoBucket = fix.New(func(t *testing.T) string {
	bucketName := FixtureBucketName(t)
	err := deleteBucket(t.Context(), FixtureGlobalS3Client(t), new(bucketName))
	if err != nil {
		t.Fatalf("Failed to delete bucket %s, %v", bucketName, err)
	}

	return bucketName
})

// FixtureCleanBucket ensures an empty fixture bucket exists for the duration
// of the test. If a bucket with the same name already exists it is deleted
// and recreated. The bucket is removed on t.Cleanup.
var FixtureCleanBucket = fix.New(func(t *testing.T) string {
	bucketName := FixtureBucketName(t)
	client := FixtureGlobalS3Client(t)
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
		err = deleteBucket(t.Context(), client, new(bucketName))
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

	t.Cleanup(func() { deleteBucket(context.Background(), client, new(bucketName)) }) //#nosec G104
	return bucketName

})

// docStore caches the DocumentStore returned by FixtureGlobalDocumentStore
// so that all tests in a run share a single instance.
var docStore docdb.DocumentStore

// FixtureGlobalDocumentStore returns a process-wide docdb.DocumentStore
// pointed at the fixture bucket and backed by the fixture S3 client.
// The instance is cached across tests.
var FixtureGlobalDocumentStore = fix.New(func(t *testing.T) docdb.DocumentStore {
	if docStore != nil {
		return docStore
	}

	documentStore := s3.NewDocumentStore(FixtureBucketName(t), FixtureGlobalS3Client(t))
	docStore = documentStore
	return docStore
})

// s3Client caches the *awss3.Client returned by FixtureGlobalS3Client so that
// all tests in a run share a single, fully configured S3 client.
var s3Client *awss3.Client

// FixtureGlobalS3Client returns a process-wide *awss3.Client built from the
// default AWS config with BaseEndpoint set from AWS_ENDPOINT_URL.
// The instance is cached across tests.
var FixtureGlobalS3Client = fix.New(func(t *testing.T) *awss3.Client {
	if s3Client != nil {
		return s3Client
	}

	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)

	if err != nil {
		t.Fatalf("Unable to load AWS SDK config, %v", err)
	}

	s3Client = awss3.NewFromConfig(cfg, func(o *awss3.Options) {
		o.BaseEndpoint = new(os.Getenv("AWS_ENDPOINT_URL"))
		o.UsePathStyle = true
	})

	return s3Client
})

// FixtureBucketName returns the bucket name used by all fixtures, taken from
// the DOCDB_BUCKET_NAME environment variable.
var FixtureBucketName = fix.New(func(t *testing.T) string {
	return os.Getenv("DOCDB_BUCKET_NAME")
})

// deleteBucket empties the bucket and then removes it. A "NoSuchBucket" error
// from either step is treated as success because the desired post-condition
// is that the bucket does not exist.
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
