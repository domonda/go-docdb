// Package s3store implements the storeconn.DocumentStore interface backed by an
// Amazon S3 (or S3-compatible) bucket. Documents are stored as individual
// objects keyed by "<docID>/<filename>/<contentHash>".
package s3store

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/ungerik/go-fs"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-docdb/storeconn"
	"github.com/domonda/go-errs"
	"github.com/domonda/go-types/uu"
)

// NewDocumentStore returns a storeconn.DocumentStore that stores document files
// as objects in the given S3 bucket using the provided S3 client.
// The bucket must already exist; this constructor does not create it.
func NewDocumentStore(bucketName string, s3Client *awss3.Client) storeconn.DocumentStore {
	return &docStore{
		client:     s3Client,
		bucketName: bucketName,
	}
}

// docStore is the S3-backed implementation of storeconn.DocumentStore.
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
// internally by the ListObjectsV2 paginator. If callback returns an error, the
// enumeration stops and the error is returned.
func (s *docStore) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) error {
	paginator := awss3.NewListObjectsV2Paginator(s.client, &awss3.ListObjectsV2Input{
		Bucket: &s.bucketName,
	})

	processedIDs := make(map[uu.ID]struct{})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return err
		}
		for _, object := range page.Contents {
			if object.Key == nil {
				return errs.New("nil object key")
			}

			id := idFromKey(*object.Key)
			if id.IsNil() {
				return errs.Errorf("can't parse ID from `%s`", *object.Key)
			}

			if _, ok := processedIDs[id]; ok {
				continue
			}
			processedIDs[id] = struct{}{}

			if err := callback(ctx, id); err != nil {
				return err
			}
		}
	}

	return nil
}

// CreateDocumentVersion uploads each of the passed files as a separate S3 object
// keyed by "<docID>/<filename>/<contentHash>". Filenames containing "/"
// are rejected because "/" is the key separator. The version argument is
// accepted for interface compatibility but not persisted at this layer;
// version tracking is the MetadataStore's responsibility.
func (s *docStore) CreateDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime, files []fs.FileReader) ([]*docdb.FileInfo, error) {
	fileInfos := make([]*docdb.FileInfo, len(files))
	for i, file := range files {
		if strings.Contains(file.Name(), "/") {
			return nil, fmt.Errorf("filename '%s' contains '/'", file.Name())
		}

		data, err := file.ReadAll()
		if err != nil {
			return nil, err
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
			return nil, err
		}
		fileInfos[i] = &docdb.FileInfo{Name: file.Name(), Size: file.Size(), Hash: hash}
	}

	return fileInfos, nil
}

// DocumentHashFileProvider lists all objects under the docID prefix, filters
// them by the passed content hashes, and returns a FileProvider over the
// matching keys. If hashes is empty an emptyFileProvider is returned.
//
// All objects are listed across as many paginated List calls as needed, so
// document versions with more than 1000 files are handled correctly.
func (s *docStore) DocumentHashFileProvider(ctx context.Context, docID uu.ID, hashes []string) (docdb.FileProvider, error) {
	if len(hashes) == 0 {
		return &emptyFileProvider{docID: docID}, nil
	}

	allKeys, err := s.listObjectKeys(ctx, docID.String()+"/")
	if err != nil {
		return nil, err
	}

	keys := filterKeysByHash(allKeys, hashes)

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

// DeleteDocument removes every object under the docID prefix.
// Returns docdb.ErrDocumentNotFound if no objects are found for the docID.
//
// Objects are listed and deleted one page at a time following ListObjectsV2
// continuation tokens, so documents with more than 1000 objects are handled
// correctly without holding every key in memory at once.
func (s *docStore) DeleteDocument(ctx context.Context, docID uu.ID) error {
	deleted, err := s.deletePrefix(ctx, docID.String()+"/")
	if err != nil {
		return err
	}
	if deleted == 0 {
		return docdb.NewErrDocumentNotFound(docID)
	}

	return nil
}

// DeleteDocumentHashes removes objects under the docID prefix whose content
// hash matches any of the passed hashes.
// Returns docdb.ErrDocumentNotFound if the document has no objects at all.
// Hashes that do not match any stored object are silently ignored.
//
// All objects are listed across as many paginated List calls as needed and
// deleted in batches, so documents with more than 1000 objects are handled
// correctly.
func (s *docStore) DeleteDocumentHashes(ctx context.Context, docID uu.ID, hashes []string) error {
	keys, err := s.listObjectKeys(ctx, docID.String()+"/")
	if err != nil {
		return err
	}
	if len(keys) == 0 {
		return docdb.NewErrDocumentNotFound(docID)
	}

	objectsToDelete := filterKeysByHash(keys, hashes)
	if len(objectsToDelete) == 0 {
		return nil
	}

	return s.deleteObjectKeys(ctx, objectsToDelete)
}

// maxDeleteObjectsPerRequest is the maximum number of objects AWS S3 accepts
// in a single DeleteObjects request.
const maxDeleteObjectsPerRequest = 1000

// listObjectKeys returns every object key under the given prefix in the bucket,
// following ListObjectsV2 continuation tokens so the result is not capped at the
// 1000-keys-per-call S3 limit.
func (s *docStore) listObjectKeys(ctx context.Context, prefix string) ([]string, error) {
	paginator := awss3.NewListObjectsV2Paginator(s.client, &awss3.ListObjectsV2Input{
		Bucket: &s.bucketName,
		Prefix: &prefix,
	})

	var keys []string
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, err
		}
		for _, obj := range page.Contents {
			if obj.Key != nil {
				keys = append(keys, *obj.Key)
			}
		}
	}

	return keys, nil
}

// deletePrefix deletes every object under the given prefix, listing and deleting
// one page at a time following ListObjectsV2 continuation tokens. Each page is
// capped at 1000 objects by S3 and so fits in a single DeleteObjects request, so
// prefixes with more than 1000 objects are handled without ever holding more
// than one page of keys in memory. It returns the number of objects deleted.
func (s *docStore) deletePrefix(ctx context.Context, prefix string) (int, error) {
	paginator := awss3.NewListObjectsV2Paginator(s.client, &awss3.ListObjectsV2Input{
		Bucket: &s.bucketName,
		Prefix: &prefix,
	})

	deleted := 0
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return deleted, err
		}
		if len(page.Contents) == 0 {
			continue
		}

		objects := make([]types.ObjectIdentifier, len(page.Contents))
		for i, obj := range page.Contents {
			objects[i] = types.ObjectIdentifier{Key: obj.Key}
		}
		if err := s.deleteObjectBatch(ctx, objects); err != nil {
			return deleted, err
		}
		deleted += len(objects)
	}

	return deleted, nil
}

// deleteObjectKeys deletes the given object keys from the bucket, splitting the
// work into batches because S3 DeleteObjects accepts at most
// maxDeleteObjectsPerRequest keys per call.
func (s *docStore) deleteObjectKeys(ctx context.Context, keys []string) error {
	for start := 0; start < len(keys); start += maxDeleteObjectsPerRequest {
		end := min(start+maxDeleteObjectsPerRequest, len(keys))

		objects := make([]types.ObjectIdentifier, end-start)
		for i, key := range keys[start:end] {
			objects[i] = types.ObjectIdentifier{Key: new(key)}
		}
		if err := s.deleteObjectBatch(ctx, objects); err != nil {
			return err
		}
	}

	return nil
}

// deleteObjectBatch issues a single DeleteObjects request for the given objects
// and returns an error if the request itself failed or S3 reported per-object
// failures. The caller must keep len(objects) within maxDeleteObjectsPerRequest.
func (s *docStore) deleteObjectBatch(ctx context.Context, objects []types.ObjectIdentifier) error {
	out, err := s.client.DeleteObjects(ctx, &awss3.DeleteObjectsInput{
		Bucket: &s.bucketName,
		Delete: &types.Delete{Objects: objects},
	})
	if err != nil {
		return err
	}
	return DeleteObjectsErr(out)
}

// DeleteObjectsErr returns a non-nil error describing the per-object failures
// that S3 reports inside an otherwise successful (HTTP 200) DeleteObjects
// response via its Errors field. S3 does not surface these as a transport error,
// so callers must check them explicitly to avoid silently leaving objects
// behind. It returns nil when no per-object failures occurred, including for a
// nil output (a nil response carries no per-object failures to report).
func DeleteObjectsErr(out *awss3.DeleteObjectsOutput) error {
	if out == nil || len(out.Errors) == 0 {
		return nil
	}
	first := out.Errors[0]
	return errs.Errorf(
		"DeleteObjects reported %d per-object failure(s); first: key=%q code=%q message=%q",
		len(out.Errors),
		aws.ToString(first.Key), aws.ToString(first.Code), aws.ToString(first.Message),
	)
}

// Key returns the S3 object key used by this package for a single
// document file in the form "<docID>/<filename>/<hash>".
func Key(docID uu.ID, filename string, hash string) string {
	return strings.Join([]string{docID.String(), filename, hash}, "/")
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

// filterKeysByHash returns the subset of keys whose content-hash component
// matches any of the passed hashes. The hashes are collected into a set and
// hashFromKey is computed once per key, so the cost is O(len(keys)+len(hashes))
// rather than the O(len(keys)*len(hashes)) of a nested scan. Each matching key
// is returned at most once even if hashes contains duplicates.
func filterKeysByHash(keys, hashes []string) []string {
	hashSet := make(map[string]struct{}, len(hashes))
	for _, hash := range hashes {
		hashSet[hash] = struct{}{}
	}

	var matched []string
	for _, key := range keys {
		if _, ok := hashSet[hashFromKey(key)]; ok {
			matched = append(matched, key)
		}
	}
	return matched
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
