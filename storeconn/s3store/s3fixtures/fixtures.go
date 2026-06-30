// Package s3fixtures provides shared test fixtures for the s3store package.
// Fixtures are lazily initialized once per test; clients come from AWS config
// and the following environment variables:
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
	"sync"
	"testing"

	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/storeconn"
	"github.com/domonda/go-docdb/storeconn/s3store"
	"github.com/domonda/go-types/uu"
)

// FixtureCreateDocument returns a helper that writes a single document file
// to the fixture bucket under the canonical "<docID>/<filename>/<hash>" key,
// using the fixture S3 client. The helper calls t.Fatal on any error.
var FixtureCreateDocument = newFixture(func(t *testing.T) func(
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
				Key:    new(s3store.Key(docID, filename, hash)),
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
var FixtureObjectExists = newFixture(func(t *testing.T) func(docID uu.ID, filename, hash string) bool {
	bucketName := FixtureCleanBucket(t)
	client := FixtureGlobalS3Client(t)

	return func(docID uu.ID, filename, hash string) bool {
		_, err := client.GetObject(
			t.Context(),
			&awss3.GetObjectInput{
				Bucket: &bucketName,
				Key:    new(s3store.Key(docID, filename, hash)),
			},
		)

		return err == nil
	}
})

// FixtureNoBucket ensures the fixture bucket does not exist by deleting it
// (and any contained objects) if present. Returns the bucket name for use
// in test assertions. Calls t.Fatal if deletion fails.
var FixtureNoBucket = newFixture(func(t *testing.T) string {
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
var FixtureCleanBucket = newFixture(func(t *testing.T) string {
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
var docStore storeconn.DocumentStore

// FixtureGlobalDocumentStore returns a process-wide storeconn.DocumentStore
// pointed at the fixture bucket and backed by the fixture S3 client.
// The instance is cached across tests.
var FixtureGlobalDocumentStore = newFixture(func(t *testing.T) storeconn.DocumentStore {
	if docStore != nil {
		return docStore
	}

	documentStore := s3store.NewDocumentStore(FixtureBucketName(t), FixtureGlobalS3Client(t))
	docStore = documentStore
	return docStore
})

// globalS3Client lazily builds the test S3 client once per process and probes
// it with a ListBuckets call. Build and probe failures are returned rather than
// fatal, so tests can skip cleanly when no S3 backend is available
// (e.g. plain `go test ./...`).
var globalS3Client = sync.OnceValues(func() (*awss3.Client, error) {
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}

	client := awss3.NewFromConfig(cfg, func(o *awss3.Options) {
		o.BaseEndpoint = new(os.Getenv("AWS_ENDPOINT_URL"))
		o.UsePathStyle = true
	})

	_, err = client.ListBuckets(ctx, &awss3.ListBucketsInput{})
	if err != nil {
		return nil, err
	}
	return client, nil
})

// FixtureGlobalS3Client returns a process-wide *awss3.Client built from the
// default AWS config with BaseEndpoint set from AWS_ENDPOINT_URL.
// The test is skipped if no S3 backend is reachable.
var FixtureGlobalS3Client = newFixture(func(t *testing.T) *awss3.Client {
	client, err := globalS3Client()
	if err != nil {
		t.Skipf("S3 test backend not available: %v", err)
	}
	return client
})

// FixtureBucketName returns the bucket name used by all fixtures, taken from
// the DOCDB_BUCKET_NAME environment variable.
var FixtureBucketName = newFixture(func(t *testing.T) string {
	return os.Getenv("DOCDB_BUCKET_NAME")
})

// deleteBucket empties the bucket and then removes it. A "NoSuchBucket" error
// from any step is treated as success because the desired post-condition is
// that the bucket does not exist. The listing follows continuation tokens and
// each page (capped at 1000 objects by S3) is deleted in its own DeleteObjects
// call, so buckets with more than 1000 objects are emptied correctly.
func deleteBucket(ctx context.Context, client *awss3.Client, bucketName *string) error {
	paginator := awss3.NewListObjectsV2Paginator(client, &awss3.ListObjectsV2Input{Bucket: bucketName})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			if strings.Contains(err.Error(), "NoSuchBucket") {
				return nil
			}
			return err
		}
		if len(page.Contents) == 0 {
			continue
		}

		objectsToDelete := make([]types.ObjectIdentifier, len(page.Contents))
		for i, obj := range page.Contents {
			objectsToDelete[i] = types.ObjectIdentifier{Key: obj.Key}
		}

		out, err := client.DeleteObjects(ctx, &awss3.DeleteObjectsInput{
			Bucket: bucketName,
			Delete: &types.Delete{
				Objects: objectsToDelete,
			},
		})
		if err != nil {
			if strings.Contains(err.Error(), "NoSuchBucket") {
				return nil
			}
			return err
		}
		// DeleteObjects returns HTTP 200 with per-object failures reported in
		// out.Errors rather than as err; surface them so teardown doesn't fail
		// later with a confusing BucketNotEmpty from DeleteBucket.
		if err := s3store.DeleteObjectsErr(out); err != nil {
			return err
		}
	}

	_, err := client.DeleteBucket(ctx, &awss3.DeleteBucketInput{Bucket: bucketName})
	if err != nil && !strings.Contains(err.Error(), "NoSuchBucket") {
		return err
	}
	return nil
}

// newFixture wraps create so its result is memoized per test: create runs at
// most once per *testing.T, and every call within that test returns the same
// value. The cache entry is dropped when the test ends.
func newFixture[V any](create func(t *testing.T) V) func(t *testing.T) V {
	var (
		mu     sync.Mutex
		values = make(map[*testing.T]V)
	)
	return func(t *testing.T) V {
		mu.Lock()
		v, cached := values[t]
		mu.Unlock()
		if cached {
			return v
		}

		v = create(t)

		mu.Lock()
		values[t] = v
		mu.Unlock()
		t.Cleanup(func() {
			mu.Lock()
			delete(values, t)
			mu.Unlock()
		})
		return v
	}
}
