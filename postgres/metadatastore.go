package postgres

import (
	"context"
	"database/sql"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

func NewMetadataStore() docdb.MetadataStore {
	return &postgresMetadataStore{}
}

type postgresMetadataStore struct{}

// TODO
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

func (store *postgresMetadataStore) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	return db.QueryValue[uu.ID](
		ctx,
		/* sql */ `
		select client_company_id from docdb.document_version
		where document_id = $1
		order by version desc
		limit 1
		`,
		docID,
	)
}

func (store *postgresMetadataStore) SetDocumentCompanyID(ctx context.Context, docID, companyID uu.ID) error {
	ids := []uu.ID{}
	err := db.QueryRows(
		ctx,
		/* sql */ `update docdb.document_version
		set client_company_id = $1
		where document_id = $2
		returning docdb.document_version.id`,
		companyID,
		docID,
	).ScanSlice(&ids)

	if err != nil {
		return err
	}

	if len(ids) == 0 {
		return sql.ErrNoRows
	}

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
