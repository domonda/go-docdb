package s3

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

func NewConn(ctx context.Context, bucketName string) (docdb.Conn, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}

	client := awss3.NewFromConfig(cfg)
	return &s3Conn{
		client:     client,
		bucketName: bucketName,
	}, nil
}

type s3Conn struct {
	client     *awss3.Client
	bucketName string
}

func (c *s3Conn) DocumentExists(ctx context.Context, docID uu.ID) (exists bool, err error) {
	_, err = c.client.GetObject(ctx, &awss3.GetObjectInput{
		Bucket: &c.bucketName,
		Key:    p(docID.String()),
	})

	if err == nil {
		return true, nil
	}

	if strings.Contains(err.Error(), "NoSuchKey") {
		return false, nil
	}

	return false, err
}

func (c *s3Conn) EnumDocumentIDs(ctx context.Context, callback func(context.Context, uu.ID) error) (err error) {
	var nextContinuationToken *string
	response := &awss3.ListObjectsV2Output{}

	fetchKeys := func() error {
		response, err = c.client.ListObjectsV2(ctx, &awss3.ListObjectsV2Input{
			Bucket:            &c.bucketName,
			ContinuationToken: nextContinuationToken,
		})

		if err != nil {
			return err
		}

		nextContinuationToken = response.NextContinuationToken
		return nil
	}

	runCallbacks := func() error {
		for _, object := range response.Contents {
			if object.Key == nil {
				return errors.New("nil object key")
			}

			id := uu.IDFrom(*object.Key)
			if id.IsNil() {
				return fmt.Errorf("key `%s` is not an ID", *object.Key)
			}

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

// TODO
func (c *s3Conn) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error {
	return nil
}

// TODO
func (c *s3Conn) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	return uu.ID{}, nil
}

// TODO
func (c *s3Conn) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error { return nil }

// TODO
func (c *s3Conn) DocumentVersions(ctx context.Context, docID uu.ID) ([]docdb.VersionTime, error) {
	return nil, nil
}

// TODO
func (c *s3Conn) LatestDocumentVersion(ctx context.Context, docID uu.ID) (docdb.VersionTime, error) {
	return docdb.VersionTime{}, nil
}

// TODO
func (c *s3Conn) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
	return nil, nil
}

// TODO
func (c *s3Conn) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error) {
	return nil, nil
}

// TODO
func (c *s3Conn) DocumentVersionFileProvider(ctx context.Context, docID uu.ID, version docdb.VersionTime) (docdb.FileProvider, error) {
	return nil, nil
}

// TODO
func (c *s3Conn) ReadDocumentVersionFile(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
	filename string,
) (data []byte, err error) {
	return nil, nil
}

// TODO
func (c *s3Conn) DeleteDocument(ctx context.Context, docID uu.ID) error { return nil }

// TODO
func (c *s3Conn) DeleteDocumentVersion(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
) (leftVersions []docdb.VersionTime, err error) {
	return nil, nil
}

// TODO
func (c *s3Conn) CreateDocument(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	files []fs.FileReader,
) (*docdb.VersionInfo, error) {
	return nil, nil
}

// TODO
func (c *s3Conn) AddDocumentVersion(
	ctx context.Context,
	docID,
	userID uu.ID,
	reason string,
	createVersion docdb.CreateVersionFunc,
	onNewVersion docdb.OnNewVersionFunc,
) error {
	return nil
}

func (c *s3Conn) RestoreDocument(ctx context.Context, doc *docdb.HashedDocument, merge bool) error {
	return nil
}
