package s3

import (
	"context"
	"errors"
	"io"
	"strings"

	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/domonda/go-docdb"
)

func FileProviderFromS3Keys(client *awss3.Client, bucketName string, keys []string) docdb.FileProvider {
	return &s3FileProvider{
		keys:       keys,
		client:     client,
		bucketName: bucketName,
	}
}

type s3FileProvider struct {
	keys       []string
	client     *awss3.Client
	bucketName string
}

func (fileProvider *s3FileProvider) HasFile(filename string) (bool, error) {
	for _, key := range fileProvider.keys {
		if filenameFromKey(key) == filename {
			return true, nil
		}
	}
	return false, nil
}

func (fileProvider *s3FileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	for _, key := range fileProvider.keys {
		if filename := filenameFromKey(key); filename != "" {
			filenames = append(filenames, filename)
		}
	}
	return filenames, nil
}

func (fileProvider *s3FileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	resp, err := fileProvider.client.GetObject(
		ctx,
		&awss3.GetObjectInput{
			Bucket: &fileProvider.bucketName,
			Key:    p(fileProvider.findKey(filename)),
		},
	)

	if err != nil {
		return nil, err
	}

	return io.ReadAll(resp.Body)
}

func (fileProvider *s3FileProvider) findKey(filename string) string {
	for _, key := range fileProvider.keys {
		if filenameFromKey(key) == filename {
			return key
		}
	}
	return ""
}

func filenameFromKey(key string) string {
	parts := strings.Split(key, "/")
	if len(parts) != 3 {
		return ""
	}

	return parts[1]
}

var ErrNoSuchFile = errors.New("no such file")

type emptyFileProvider struct{}

func (fileProvider *emptyFileProvider) HasFile(filename string) (bool, error) {
	return false, nil
}

func (fileProvider *emptyFileProvider) ListFiles(ctx context.Context) (filenames []string, err error) {
	return filenames, nil
}

func (fileProvider *emptyFileProvider) ReadFile(ctx context.Context, filename string) ([]byte, error) {
	return nil, ErrNoSuchFile
}
