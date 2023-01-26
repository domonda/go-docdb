package hashdb

import (
	"bytes"
	"context"
	"fmt"

	"github.com/domonda/go-errs"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

type HashFunc func(data []byte) (hash string)

type Files interface {
	Create(ctx context.Context, data []byte) (hash string, err error)
	Read(ctx context.Context, hash string) ([]byte, error)
	Delete(ctx context.Context, hash string) error
}

type S3Files struct {
	client     *s3.Client
	bucketName string
	hashFunc   HashFunc
}

func NewS3Files(ctx context.Context, bucketName string, hashFunc HashFunc) (Files, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}
	client := s3.NewFromConfig(cfg)
	return &S3Files{
		client:     client,
		bucketName: bucketName,
		hashFunc:   hashFunc,
	}, nil
}

func (f *S3Files) key(hash string) string {
	return "/" + hash
}

func (f *S3Files) Create(ctx context.Context, data []byte) (hash string, err error) {
	hash = f.hashFunc(data)
	key := f.key(hash)
	_, err = f.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: &f.bucketName,
		Key:    &key,
		Body:   bytes.NewReader(data),
	})
	return hash, nil
}

func (f *S3Files) Read(ctx context.Context, hash string) ([]byte, error) {
	key := f.key(hash)
	out, err := f.client.GetObject(
		ctx,
		&s3.GetObjectInput{
			Bucket: &f.bucketName,
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
	if h := f.hashFunc(data); h != hash {
		return nil, fmt.Errorf("read content hash %s instead of requested %s", h, hash)
	}
	return data, nil
}

func (f *S3Files) Delete(ctx context.Context, hash string) error {
	key := f.key(hash)
	_, err := f.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: &f.bucketName,
		Key:    &key,
	})
	if isErrNotFound(err) {
		return fmt.Errorf("object %s %w", key, errs.ErrNotFound)
	}
	return err
}

func isErrNotFound(err error) bool {
	return errs.Type[*types.NotFound](err)
}
