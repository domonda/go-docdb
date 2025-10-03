package postgres

import (
	"context"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

func NewReadOnlyMetadataStore() docdb.MetadataStore {
	return &readonlyMetadataStore{}
}

type readonlyMetadataStore struct {
	postgresMetadataStore
}

func (store *readonlyMetadataStore) AddDocumentVersion(
	ctx context.Context,
	newVersion docdb.VersionTime,
	previousVersion docdb.VersionTime,
	docID,
	companyID,
	userID uu.ID,
	reason string,
	addedFiles []*docdb.FileInfo,
	modifiedFiles []*docdb.FileInfo,
	removedFiles []string,
) (*docdb.VersionInfo, error) {
	return nil, nil
}

func (store *readonlyMetadataStore) CreateDocument(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	files []fs.FileReader,
) (*docdb.VersionInfo, error) {
	return nil, nil
}

func (store *readonlyMetadataStore) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error {
	return nil
}

func (store *readonlyMetadataStore) DeleteDocument(ctx context.Context, docID uu.ID) error {
	return nil
}

func (store *readonlyMetadataStore) DeleteDocumentVersion(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
) (
	leftVersions []docdb.VersionTime,
	hashesToDelete []string,
	err error,
) {
	return nil, nil, nil
}
