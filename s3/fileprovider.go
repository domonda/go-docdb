package s3

import (
	"context"
	"errors"
	"io"
	"strings"

	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
)

// FileProviderFromKeys returns a docdb.FileProvider that reads files of the
// given document from S3 using the passed set of fully qualified object keys.
// All keys must belong to the same docID and have the form
// "<docID>/<filename>/<hash>".
func FileProviderFromKeys(client *awss3.Client, bucketName string, docID uu.ID, keys []string) docdb.FileProvider {
	return &fileProvider{
		docID:      docID,
		keys:       keys,
		client:     client,
		bucketName: bucketName,
	}
}

// fileProvider implements docdb.FileProvider over a pre-computed list of S3
// object keys for a single document. The docID is carried so that not-found
// errors can be wrapped as docdb.ErrDocumentFileNotFound with full context.
type fileProvider struct {
	docID      uu.ID
	keys       []string
	client     *awss3.Client
	bucketName string
}

// HasFile reports whether any of the provider's keys maps to the given
// filename. It does not touch S3.
func (p *fileProvider) HasFile(filename string) (bool, error) {
	for _, key := range p.keys {
		if filenameFromKey(key) == filename {
			return true, nil
		}
	}
	return false, nil
}

// ListFiles returns the filenames extracted from the provider's keys.
// It does not touch S3.
func (p *fileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	for _, key := range p.keys {
		if filename := filenameFromKey(key); filename != "" {
			filenames = append(filenames, filename)
		}
	}
	return filenames, nil
}

// ReadFile fetches the object matching the passed filename and returns its
// full contents. Returns docdb.ErrDocumentFileNotFound if no key matches
// the filename, or if S3 reports NoSuchKey for the resolved object.
func (p *fileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	key := p.findKey(filename)
	if key == "" {
		return nil, docdb.NewErrDocumentFileNotFound(p.docID, filename)
	}

	resp, err := p.client.GetObject(
		ctx,
		&awss3.GetObjectInput{
			Bucket: &p.bucketName,
			Key:    new(key),
		},
	)
	if err != nil {
		if _, ok := errors.AsType[*types.NoSuchKey](err); ok {
			return nil, docdb.NewErrDocumentFileNotFound(p.docID, filename)
		}
		return nil, err
	}
	defer resp.Body.Close()

	return io.ReadAll(resp.Body)
}

// findKey returns the first key whose filename component matches, or ""
// if no such key exists.
func (p *fileProvider) findKey(filename string) string {
	for _, key := range p.keys {
		if filenameFromKey(key) == filename {
			return key
		}
	}
	return ""
}

// filenameFromKey parses the filename component (parts[1]) out of an S3 key
// in the "<docID>/<filename>/<hash>" form. Returns "" if the key has an
// unexpected structure.
func filenameFromKey(key string) string {
	parts := strings.Split(key, "/")
	if len(parts) != 3 {
		return ""
	}

	return parts[1]
}

// emptyFileProvider is returned by DocumentHashFileProvider when the caller
// supplies no hashes. It has no files and always reports ErrDocumentFileNotFound
// on read, scoped to the provided docID.
type emptyFileProvider struct {
	docID uu.ID
}

// HasFile always returns false.
func (p *emptyFileProvider) HasFile(filename string) (bool, error) {
	return false, nil
}

// ListFiles always returns an empty list.
func (p *emptyFileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	return nil, nil
}

// ReadFile always returns docdb.ErrDocumentFileNotFound for the provider's docID.
func (p *emptyFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	return nil, docdb.NewErrDocumentFileNotFound(p.docID, filename)
}
