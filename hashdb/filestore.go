package hashdb

import (
	"bytes"
	"context"
	"errors"
	"fmt"

	"github.com/domonda/go-errs"
	"github.com/ungerik/go-fs"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

type HashFunc func(data []byte) (hash string)

type FileStore interface {
	fmt.Stringer

	Create(ctx context.Context, data []byte) (hash string, err error)
	Delete(ctx context.Context, hash string) error
	Read(ctx context.Context, hash string) ([]byte, error)
}

///////////////////////////////////////////////////////////////////////////////

type localFileStore struct {
	baseDir  fs.File
	hashFunc HashFunc
}

func NewLocalFileStore(baseDir fs.File, hashFunc HashFunc) (FileStore, error) {
	if err := baseDir.CheckIsDir(); err != nil {
		return nil, err
	}
	return &localFileStore{baseDir, hashFunc}, nil
}

func (l *localFileStore) String() string {
	return l.baseDir.String()
}

func (l *localFileStore) file(hash string) fs.File {
	return l.baseDir.Join(hash)
}

func (l *localFileStore) Create(ctx context.Context, data []byte) (hash string, err error) {
	hash = l.hashFunc(data)
	file := l.file(hash)
	if file.Exists() {
		return hash, fmt.Errorf("hash %s %w", hash, fs.NewErrAlreadyExists(file))
	}
	return hash, file.WriteAllContext(ctx, data)
}

func (l *localFileStore) Delete(ctx context.Context, hash string) error {
	return l.file(hash).Remove()
}

func (l *localFileStore) Read(ctx context.Context, hash string) ([]byte, error) {
	return l.file(hash).ReadAllContext(ctx)
}

///////////////////////////////////////////////////////////////////////////////

type s3FileStore struct {
	client     *s3.Client
	bucketName string
	hashFunc   HashFunc
}

func NewS3FileStore(ctx context.Context, bucketName string, hashFunc HashFunc) (FileStore, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}
	fs := &s3FileStore{
		client:     s3.NewFromConfig(cfg),
		bucketName: bucketName,
		hashFunc:   hashFunc,
	}
	err = fs.validate(ctx)
	if err != nil {
		return nil, err
	}
	return fs, nil
}

func (s *s3FileStore) String() string {
	return "s3://" + s.bucketName
}

func (s *s3FileStore) validate(ctx context.Context) error {
	_, err := s.client.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: &s.bucketName})
	if err != nil {
		var errNoSuchBucket *types.NoSuchBucket
		if errors.As(err, &errNoSuchBucket) || isErrNotFound(err) {
			return fmt.Errorf("bucket %s %w", s.bucketName, errs.ErrNotFound)
		}
		return err
	}
	return nil
}

func (*s3FileStore) key(hash string) string {
	return "/" + hash
}

func (s *s3FileStore) Create(ctx context.Context, data []byte) (hash string, err error) {
	hash = s.hashFunc(data)
	key := s.key(hash)
	_, err = s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: &s.bucketName,
		Key:    &key,
		Body:   bytes.NewReader(data),
	})
	return hash, err
}

func (s *s3FileStore) Delete(ctx context.Context, hash string) error {
	key := s.key(hash)
	_, err := s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: &s.bucketName,
		Key:    &key,
	})
	if isErrNotFound(err) {
		return fmt.Errorf("object %s %w", key, errs.ErrNotFound)
	}
	return err
}

func (s *s3FileStore) Read(ctx context.Context, hash string) ([]byte, error) {
	key := s.key(hash)
	out, err := s.client.GetObject(
		ctx,
		&s3.GetObjectInput{
			Bucket: &s.bucketName,
			Key:    &key,
		},
	)
	if err != nil {
		if isErrNotFound(err) {
			return nil, fmt.Errorf("object %s %w", key, errs.ErrNotFound)
		}
		return nil, err
	}
	defer out.Body.Close()

	data := make([]byte, int(out.ContentLength))
	n, err := out.Body.Read(data)
	if err != nil {
		return nil, err
	}
	if n < int(out.ContentLength) {
		return nil, fmt.Errorf("read %d bytes from body but content-length is %d", n, out.ContentLength)
	}
	if h := s.hashFunc(data); h != hash {
		return nil, fmt.Errorf("read content hash %s instead of requested %s", h, hash)
	}
	return data, nil
}

func isErrNotFound(err error) bool {
	var errNotFound *types.NotFound
	return errors.As(err, &errNotFound)
}
