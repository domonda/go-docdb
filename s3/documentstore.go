// Package s3 implements the docdb.DocumentStore interface backed by an
// Amazon S3 (or S3-compatible) bucket. Documents are stored as individual
// objects keyed by "<docID>/<filename>/<contentHash>".
package s3

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"strings"

	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
)

// NewDocumentStore returns a docdb.DocumentStore that stores document files
// as objects in the given S3 bucket using the provided S3 client.
// The bucket must already exist; this constructor does not create it.
func NewDocumentStore(bucketName string, s3Client *awss3.Client) docdb.DocumentStore {
	return &docStore{
		client:     s3Client,
		bucketName: bucketName,
	}
}

// docStore is the S3-backed implementation of docdb.DocumentStore.
type docStore struct {
	client     *awss3.Client
	bucketName string
}

// DocumentExists returns true if any object exists under the prefix of the
// passed docID in the configured bucket.
func (s *docStore) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	response, err := s.client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{
		Bucket:  &s.bucketName,
		Prefix:  new(docID.String() + "/"),
		MaxKeys: new(int32(1)),
	})
	if err != nil {
		return false, err
	}

	if len(response.Contents) > 0 {
		return true, nil
	}

	return false, err
}

// EnumDocumentIDs iterates every object in the bucket, extracts the docID from
// each key, and calls callback once per unique docID. Pagination is handled
// internally via continuation tokens. If callback returns an error, the
// enumeration stops and the error is returned.
func (s *docStore) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) (err error) {
	enumerator := newDocumentEnumerator(
		s.client,
		s.bucketName,
		callback,
	)

	return enumerator.Run(ctx)
}

// CreateDocument uploads each of the passed files as a separate S3 object
// keyed by "<docID>/<filename>/<contentHash>". Filenames containing "/"
// are rejected because "/" is the key separator. The version argument is
// accepted for interface compatibility but not persisted at this layer;
// version tracking is the MetadataStore's responsibility.
func (s *docStore) CreateDocument(ctx context.Context, docID uu.ID, version docdb.VersionTime, files []fs.FileReader) error {
	for _, file := range files {
		if strings.Contains(file.Name(), "/") {
			return fmt.Errorf("filename '%s' contains '/'", file.Name())
		}

		data, err := file.ReadAll()
		if err != nil {
			return err
		}
		hash := docdb.ContentHash(data)
		_, err = s.client.PutObject(
			ctx,
			&awss3.PutObjectInput{
				Bucket: &s.bucketName,
				Key:    new(Key(docID, file.Name(), hash)),
				Body:   bytes.NewReader(data),
			},
		)
		if err != nil {
			return err
		}
	}

	return nil
}

// DocumentHashFileProvider lists all objects under the docID prefix, filters
// them by the passed content hashes, and returns a FileProvider over the
// matching keys. If hashes is empty an emptyFileProvider is returned.
//
// Note: the underlying List call caps at 1000 objects, so this assumes a
// document version has at most 1000 files.
func (s *docStore) DocumentHashFileProvider(ctx context.Context, docID uu.ID, hashes []string) (docdb.FileProvider, error) {
	if len(hashes) == 0 {
		return &emptyFileProvider{docID: docID}, nil
	}

	// assume a version has max 1000 files
	response, err := s.client.ListObjectsV2(
		ctx,
		&awss3.ListObjectsV2Input{
			Bucket: &s.bucketName,
			Prefix: new(docID.String() + "/"),
		},
	)

	if err != nil {
		return nil, err
	}

	keys := []string{}
	for _, obj := range response.Contents {
		for _, hash := range hashes {
			if hashFromKey(*obj.Key) == hash {
				keys = append(keys, *obj.Key)
			}
		}
	}

	return FileProviderFromKeys(s.client, s.bucketName, docID, keys), nil
}

// ReadDocumentHashFile fetches the single object at key
// "<docID>/<filename>/<hash>" and returns its full content.
// Returns docdb.ErrDocumentFileNotFound if no such object exists.
func (s *docStore) ReadDocumentHashFile(ctx context.Context, docID uu.ID, filename, hash string) (data []byte, err error) {
	res, err := s.client.GetObject(
		ctx,
		&awss3.GetObjectInput{
			Bucket: new(s.bucketName),
			Key:    new(Key(docID, filename, hash)),
		},
	)
	if err != nil {
		if _, ok := errors.AsType[*types.NoSuchKey](err); ok {
			return nil, docdb.NewErrDocumentFileNotFound(docID, filename)
		}
		return nil, err
	}
	defer res.Body.Close()

	return io.ReadAll(res.Body)
}

// DeleteDocument removes every object under the docID prefix in a single
// bulk DeleteObjects call. Returns docdb.ErrDocumentNotFound if no objects
// are found for the docID.
//
// Note: the underlying List call caps at 1000 objects.
func (s *docStore) DeleteDocument(ctx context.Context, docID uu.ID) error {
	// assuming there are max 1000 objects
	response, err := s.client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{
		Bucket: &s.bucketName,
		Prefix: new(docID.String() + "/"),
	})
	if err != nil {
		return err
	}
	if len(response.Contents) == 0 {
		return docdb.NewErrDocumentNotFound(docID)
	}

	objectsToDelete := make([]types.ObjectIdentifier, len(response.Contents))
	for i, obj := range response.Contents {
		objectsToDelete[i] = types.ObjectIdentifier{Key: obj.Key}
	}

	_, err = s.client.DeleteObjects(
		ctx,
		&awss3.DeleteObjectsInput{
			Bucket: new(s.bucketName),
			Delete: &types.Delete{
				Objects: objectsToDelete,
			},
		},
	)

	return err
}

// DeleteDocumentHashes removes objects under the docID prefix whose content
// hash matches any of the passed hashes.
// Returns docdb.ErrDocumentNotFound if the document has no objects at all.
// Hashes that do not match any stored object are silently ignored.
//
// Note: the underlying List call caps at 1000 objects.
func (s *docStore) DeleteDocumentHashes(ctx context.Context, docID uu.ID, hashes []string) error {
	// assuming there are max 1000 objects
	response, err := s.client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{
		Bucket: &s.bucketName,
		Prefix: new(docID.String() + "/"),
	})
	if err != nil {
		return err
	}
	if len(response.Contents) == 0 {
		return docdb.NewErrDocumentNotFound(docID)
	}

	objectsToDelete := []types.ObjectIdentifier{}
	for _, obj := range response.Contents {
		for _, hash := range hashes {
			if hashFromKey(*obj.Key) == hash {
				objectsToDelete = append(objectsToDelete, types.ObjectIdentifier{Key: obj.Key})
			}
		}
	}
	if len(objectsToDelete) == 0 {
		return nil
	}

	_, err = s.client.DeleteObjects(
		ctx,
		&awss3.DeleteObjectsInput{
			Bucket: new(s.bucketName),
			Delete: &types.Delete{
				Objects: objectsToDelete,
			},
		},
	)

	return err
}

// Key returns the S3 object key used by this package for a single
// document file in the form "<docID>/<filename>/<hash>".
func Key(docID uu.ID, filename string, hash string) string {
	return strings.Join([]string{docID.String(), filename, hash}, "/")
}

// documentEnumerator walks every object in the bucket, groups them by docID,
// and invokes a callback once per unique docID. Pagination state is carried
// across List calls via nextContinuationToken.
type documentEnumerator struct {
	client                *awss3.Client
	nextContinuationToken *string
	bucketName            string
	processedIDs          map[uu.ID]struct{}
	callback              func(context.Context, uu.ID) error
}

// newDocumentEnumerator constructs a documentEnumerator for the given bucket
// and callback with an empty set of processed IDs.
func newDocumentEnumerator(client *awss3.Client, bucketName string, callback func(context.Context, uu.ID) error) *documentEnumerator {
	return &documentEnumerator{
		client:       client,
		bucketName:   bucketName,
		processedIDs: map[uu.ID]struct{}{},
		callback:     callback,
	}
}

// Run executes one or more List cycles until all pages have been consumed
// or a cycle returns an error.
func (e *documentEnumerator) Run(ctx context.Context) error {
	if err := e.runCycle(ctx); err != nil {
		return err
	}

	for e.nextContinuationToken != nil {
		if err := e.runCycle(ctx); err != nil {
			return err
		}
	}

	return nil
}

// runCycle performs one List call and invokes the callback for every new
// docID found in the returned page.
func (e *documentEnumerator) runCycle(ctx context.Context) error {
	resp, err := e.getResponse(ctx)
	if err != nil {
		return err
	}

	return e.runCallbacks(ctx, resp)
}

// getResponse issues a single ListObjectsV2 call using the current
// continuation token and updates nextContinuationToken from the response.
func (e *documentEnumerator) getResponse(ctx context.Context) (*awss3.ListObjectsV2Output, error) {
	response, err := e.client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{
		Bucket:            &e.bucketName,
		ContinuationToken: e.nextContinuationToken,
	})

	if err != nil {
		return nil, err
	}

	e.nextContinuationToken = response.NextContinuationToken
	return response, nil
}

// runCallbacks iterates the objects of a List response, skips docIDs already
// seen in previous pages, records newly seen IDs, and invokes the callback
// once per new ID. A malformed or unparsable key aborts the enumeration.
func (e *documentEnumerator) runCallbacks(ctx context.Context, response *awss3.ListObjectsV2Output) error {
	for _, object := range response.Contents {
		if object.Key == nil {
			return errors.New("nil object key")
		}

		id := idFromKey(*object.Key)
		if id.IsNil() {
			return fmt.Errorf("can't parse ID from `%s`", *object.Key)
		}

		if _, ok := e.processedIDs[id]; ok {
			continue
		}

		e.processedIDs[id] = struct{}{}

		if err := e.callback(ctx, id); err != nil {
			return err
		}
	}

	return nil
}

// idFromKey parses the docID component (parts[0]) out of an S3 key in the
// "<docID>/<filename>/<hash>" form. Returns uu.IDNil if the key has an
// unexpected structure or an unparsable ID.
func idFromKey(key string) uu.ID {
	parts := strings.Split(key, "/")
	if len(parts) != 3 {
		return uu.IDNil
	}

	return uu.IDFrom(parts[0])
}

// hashFromKey parses the content-hash component (parts[2]) out of an S3 key
// in the "<docID>/<filename>/<hash>" form. Returns "" if the key has an
// unexpected structure.
func hashFromKey(key string) string {
	parts := strings.Split(key, "/")
	if len(parts) != 3 {
		return ""
	}

	return parts[2]
}
