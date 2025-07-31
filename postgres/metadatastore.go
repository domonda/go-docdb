package postgres

import (
	"context"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

func NewMetadataStore() docdb.MetadataStore {
	return &postgresMetadataStore{}
}

type postgresMetadataStore struct{}

func (store *postgresMetadataStore) CreateDocument(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	files []fs.FileReader,
) (*docdb.VersionInfo, error)

func (store *postgresMetadataStore) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error)

func (store *postgresMetadataStore) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error

func (store *postgresMetadataStore) DocumentVersions(ctx context.Context, docID uu.ID) ([]docdb.VersionTime, error)

func (store *postgresMetadataStore) LatestDocumentVersion(ctx context.Context, docID uu.ID) (docdb.VersionTime, error)

func (store *postgresMetadataStore) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error

func (store *postgresMetadataStore) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error)

func (store *postgresMetadataStore) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error)

func (store *postgresMetadataStore) DeleteDocument(ctx context.Context, docID uu.ID) error

func (store *postgresMetadataStore) DeleteDocumentVersion(ctx context.Context, docID uu.ID, version docdb.VersionTime) (leftVersions []docdb.VersionTime, hashesToDelete []string, err error)
