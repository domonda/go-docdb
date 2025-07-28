package s3

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"

	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

func NewS3DocumentStore(ctx context.Context, bucketName string) (docdb.DocumentStore, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}

	client := awss3.NewFromConfig(cfg)
	return &s3DocStore{
		client:     client,
		bucketName: bucketName,
	}, nil
}

type s3DocStore struct {
	client     *awss3.Client
	bucketName string
}

func (store *s3DocStore) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	response, err := store.client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{
		Bucket:  &store.bucketName,
		Prefix:  p(docID.String() + "/"),
		MaxKeys: p[int32](1),
	})

	if err != nil {
		return false, err
	}

	if len(response.Contents) > 0 {
		return true, nil
	}

	return false, err
}

func (store *s3DocStore) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) (err error) {
	var nextContinuationToken *string
	response := &awss3.ListObjectsV2Output{}

	fetchKeys := func() error {
		response, err = store.client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{
			Bucket:            &store.bucketName,
			ContinuationToken: nextContinuationToken,
		})

		if err != nil {
			return err
		}

		nextContinuationToken = response.NextContinuationToken
		return nil
	}

	processedIDs := map[uu.ID]struct{}{}
	runCallbacks := func() error {
		for _, object := range response.Contents {
			if object.Key == nil {
				return errors.New("nil object key")
			}

			id := idFromKey(*object.Key)
			if id.IsNil() {
				return fmt.Errorf("can't parse ID from `%s`", *object.Key)
			}

			if _, ok := processedIDs[id]; ok {
				continue
			}

			processedIDs[id] = struct{}{}

			if err = callback(ctx, id); err != nil {
				return err
			}
		}

		return nil
	}

	runCycle := func() error {
		if err = fetchKeys(); err != nil {
			return err
		}
		if err = runCallbacks(); err != nil {
			return err
		}

		return nil
	}

	if err = runCycle(); err != nil {
		return err
	}

	for nextContinuationToken != nil {
		if err = runCycle(); err != nil {
			return err
		}
	}

	return nil
}

func (store *s3DocStore) CreateDocument(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
	files []fs.FileReader,
) error {
	for _, file := range files {
		if _, err := store.client.PutObject(
			ctx,
			&awss3.PutObjectInput{
				Bucket: &store.bucketName,
				Key:    p(getKey(docID, version, file.Name())),
			},
		); err != nil {
			return err
		}
	}

	return nil
}

func (store *s3DocStore) DocumentVersionFileProvider(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
) (docdb.FileProvider, error) {
	// assume a version has max 1000 files
	response, err := store.client.ListObjectsV2(
		ctx,
		&awss3.ListObjectsV2Input{
			Bucket: &store.bucketName,
			Prefix: p(docID.String() + "/" + version.String() + "/"),
		},
	)

	if err != nil {
		return nil, err
	}

	keys := []string{}
	for _, obj := range response.Contents {
		keys = append(keys, *obj.Key)
	}

	return FileProviderFromS3Keys(store.client, store.bucketName, keys), nil
}

func (store *s3DocStore) ReadDocumentVersionFile(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
	filename string,
) (data []byte, err error) {
	res, err := store.client.GetObject(
		ctx,
		&awss3.GetObjectInput{
			Bucket: p(store.bucketName),
			Key:    p(getKey(docID, version, filename)),
		},
	)

	if err != nil {
		return nil, err
	}

	return io.ReadAll(res.Body)
}

func getKey(docID uu.ID, version docdb.VersionTime, filename string) string {
	return strings.Join([]string{docID.String(), version.String(), filename}, "/")
}

func idFromKey(key string) uu.ID {
	parts := strings.Split(key, "/")
	if len(parts) != 3 {
		return uu.IDNil
	}

	return uu.IDFrom(parts[0])
}
