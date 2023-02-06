package hashdb

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"

	"github.com/domonda/go-errs"
)

type s3FileStore struct {
	client     *s3.Client
	uploader   *manager.Uploader
	bucketName string
	hashFunc   HashFunc
}

func NewS3FileStore(ctx context.Context, bucketName string, hashFunc HashFunc) (FileStore, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}
	client := s3.NewFromConfig(cfg)
	uploader := manager.NewUploader(client)
	fs := &s3FileStore{
		client:     client,
		uploader:   uploader,
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
		if errors.As(err, &errNoSuchBucket) || isS3ErrNotFound(err) {
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
	_, err = s.uploader.Upload(ctx, &s3.PutObjectInput{
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
	if isS3ErrNotFound(err) {
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
		if isS3ErrNotFound(err) {
			return nil, fmt.Errorf("object %s %w", key, errs.ErrNotFound)
		}
		return nil, err
	}
	defer out.Body.Close()

	data, err := io.ReadAll(out.Body)
	if err != nil {
		return nil, err
	}
	if h := s.hashFunc(data); h != hash {
		return nil, fmt.Errorf("read content hash %s instead of requested %s", h, hash)
	}
	return data, nil
}

func isS3ErrNotFound(err error) bool {
	var errNotFound *types.NotFound
	return errors.As(err, &errNotFound)
}
