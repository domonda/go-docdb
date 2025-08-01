package postgres

import (
	"context"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-sqldb"
	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

func NewMetadataStore(conn sqldb.Connection) docdb.MetadataStore {
	return &postgresMetadataStore{
		conn: conn,
	}
}

type postgresMetadataStore struct {
	conn sqldb.Connection
}

func (store *postgresMetadataStore) CreateDocument(
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
func (store *postgresMetadataStore) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	return uu.ID{}, nil
}

// TODO
func (store *postgresMetadataStore) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error {
	return nil
}

// TODO
func (store *postgresMetadataStore) DocumentVersions(ctx context.Context, docID uu.ID) ([]docdb.VersionTime, error) {
	return nil, nil
}

// TODO
func (store *postgresMetadataStore) LatestDocumentVersion(ctx context.Context, docID uu.ID) (docdb.VersionTime, error) {
	return docdb.VersionTime{}, nil
}

// TODO
func (store *postgresMetadataStore) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error {
	return nil
}

// TODO
func (store *postgresMetadataStore) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
	return nil, nil
}

// TODO
func (store *postgresMetadataStore) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error) {
	return nil, nil
}

// TODO
func (store *postgresMetadataStore) DeleteDocument(ctx context.Context, docID uu.ID) error {
	return nil
}

// TODO
func (store *postgresMetadataStore) DeleteDocumentVersion(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
) (leftVersions []docdb.VersionTime, hashesToDelete []string, err error) {
	return nil, nil, nil
}
