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

func NewS3DocumentStore(bucketName string, s3Client *awss3.Client) docdb.DocumentStore {
	return &s3DocStore{
		client:     s3Client,
		bucketName: bucketName,
	}
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
	enumerator := newDocumentEnumerator(
		store.client,
		callback,
		store.bucketName,
	)

	return enumerator.Run(ctx)
}

func (store *s3DocStore) CreateDocument(
	ctx context.Context,
	docID uu.ID,
	files []fs.FileReader,
) error {
	for _, file := range files {
		if strings.Contains(file.Name(), "/") {
			return fmt.Errorf("filename '%s' contains '/'", file.Name())
		}

		data, err := file.ReadAll()
		if err != nil {
			return err
		}
		hash := docdb.ContentHash(data)
		if _, err := store.client.PutObject(
			ctx,
			&awss3.PutObjectInput{
				Bucket: &store.bucketName,
				Key:    p(Key(docID, file.Name(), hash)),
				Body:   bytes.NewReader(data),
			},
		); err != nil {
			return err
		}
	}

	return nil
}

func (store *s3DocStore) DocumentHashFileProvider(
	ctx context.Context,
	docID uu.ID,
	hashes []string,
) (docdb.FileProvider, error) {
	if len(hashes) == 0 {
		return &emptyFileProvider{}, nil
	}

	// assume a version has max 1000 files
	response, err := store.client.ListObjectsV2(
		ctx,
		&awss3.ListObjectsV2Input{
			Bucket: &store.bucketName,
			Prefix: p(docID.String() + "/"),
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

	return FileProviderFromS3Keys(store.client, store.bucketName, keys), nil
}

func (store *s3DocStore) ReadDocumentHashFile(
	ctx context.Context,
	docID uu.ID,
	filename,
	hash string,
) (data []byte, err error) {
	res, err := store.client.GetObject(
		ctx,
		&awss3.GetObjectInput{
			Bucket: p(store.bucketName),
			Key:    p(Key(docID, filename, hash)),
		},
	)

	if err != nil {
		return nil, err
	}

	defer res.Body.Close()
	return io.ReadAll(res.Body)
}

func (store *s3DocStore) DeleteDocument(ctx context.Context, docID uu.ID) error {
	// assuming there are max 1000 objects
	response, err := store.client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{
		Bucket: &store.bucketName,
		Prefix: p(docID.String() + "/"),
	})

	if err != nil {
		return err
	}

	objectsToDelete := []types.ObjectIdentifier{}
	for _, obj := range response.Contents {
		objectsToDelete = append(objectsToDelete, types.ObjectIdentifier{Key: obj.Key})
	}

	_, err = store.client.DeleteObjects(
		ctx,
		&awss3.DeleteObjectsInput{
			Bucket: p(store.bucketName),
			Delete: &types.Delete{
				Objects: objectsToDelete,
			},
		},
	)

	return err
}

func (store *s3DocStore) DeleteDocumentHashes(ctx context.Context, docID uu.ID, hashes []string) error {
	// assuming there are max 1000 objects
	response, err := store.client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{
		Bucket: &store.bucketName,
		Prefix: p(docID.String() + "/"),
	})

	if err != nil {
		return err
	}

	objectsToDelete := []types.ObjectIdentifier{}
	for _, obj := range response.Contents {
		for _, hash := range hashes {
			if hashFromKey(*obj.Key) == hash {
				objectsToDelete = append(objectsToDelete, types.ObjectIdentifier{Key: obj.Key})
			}
		}
	}

	_, err = store.client.DeleteObjects(
		ctx,
		&awss3.DeleteObjectsInput{
			Bucket: p(store.bucketName),
			Delete: &types.Delete{
				Objects: objectsToDelete,
			},
		},
	)

	return err
}

func Key(docID uu.ID, filename string, hash string) string {
	return strings.Join([]string{docID.String(), filename, hash}, "/")
}

type documentEnumerator struct {
	client                *awss3.Client
	nextContinuationToken *string
	bucketName            string
	processedIDs          map[uu.ID]struct{}
	callback              func(context.Context, uu.ID) error
}

func newDocumentEnumerator(
	client *awss3.Client,
	callback func(context.Context, uu.ID) error,
	bucketName string,
) *documentEnumerator {
	return &documentEnumerator{
		client:       client,
		bucketName:   bucketName,
		processedIDs: map[uu.ID]struct{}{},
		callback:     callback,
	}
}

func (enumerator *documentEnumerator) Run(ctx context.Context) error {
	if err := enumerator.runCycle(ctx); err != nil {
		return err
	}

	for enumerator.nextContinuationToken != nil {
		if err := enumerator.runCycle(ctx); err != nil {
			return err
		}
	}

	return nil
}

func (enumerator *documentEnumerator) runCycle(ctx context.Context) error {
	resp, err := enumerator.getResponse(ctx)
	if err != nil {
		return err
	}

	return enumerator.runCallbacks(ctx, resp)
}

func (enumerator *documentEnumerator) getResponse(ctx context.Context) (*awss3.ListObjectsV2Output, error) {
	response, err := enumerator.client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{
		Bucket:            &enumerator.bucketName,
		ContinuationToken: enumerator.nextContinuationToken,
	})

	if err != nil {
		return nil, err
	}

	enumerator.nextContinuationToken = response.NextContinuationToken
	return response, nil
}

func (enumerator *documentEnumerator) runCallbacks(ctx context.Context, response *awss3.ListObjectsV2Output) error {
	for _, object := range response.Contents {
		if object.Key == nil {
			return errors.New("nil object key")
		}

		id := idFromKey(*object.Key)
		if id.IsNil() {
			return fmt.Errorf("can't parse ID from `%s`", *object.Key)
		}

		if _, ok := enumerator.processedIDs[id]; ok {
			continue
		}

		enumerator.processedIDs[id] = struct{}{}

		if err := enumerator.callback(ctx, id); err != nil {
			return err
		}
	}

	return nil
}

func idFromKey(key string) uu.ID {
	parts := strings.Split(key, "/")
	if len(parts) != 3 {
		return uu.IDNil
	}

	return uu.IDFrom(parts[0])
}

func hashFromKey(key string) string {
	parts := strings.Split(key, "/")
	if len(parts) != 3 {
		return ""
	}

	return parts[2]
}
