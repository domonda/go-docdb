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

func (store *postgresMetadataStore) DocumentVersions(ctx context.Context, docID uu.ID) ([]docdb.VersionTime, error) {
	versions := []docdb.VersionTime{}

	err := db.QueryRows(
		ctx,
		/* sql */ `
		select version
		from docdb.document_version
		where document_id = $1
		order by version desc
		`,
		docID,
	).ScanSlice(&versions)

	if err != nil {
		return nil, err
	}

	if len(versions) == 0 {
		return nil, sql.ErrNoRows
	}

	return versions, err
}

func (store *postgresMetadataStore) LatestDocumentVersion(ctx context.Context, docID uu.ID) (docdb.VersionTime, error) {
	return db.QueryValue[docdb.VersionTime](
		ctx,
		/* sql */ `
		select version
		from docdb.document_version
		where document_id = $1
		order by version desc
		limit 1
		`,
		docID,
	)
}

func (store *postgresMetadataStore) EnumCompanyDocumentIDs(ctx context.Context, companyID uu.ID, callback func(context.Context, uu.ID) error) error {
	ids := []uu.ID{}

	err := db.QueryRows(
		ctx,
		/* sql */ `
		select distinct document_id
		from docdb.document_version
		where client_company_id = $1
		`,
		companyID,
	).ScanSlice(&ids)

	if err != nil {
		return err
	}

	if len(ids) == 0 {
		return sql.ErrNoRows
	}

	for _, id := range ids {
		if err = callback(ctx, id); err != nil {
			return err
		}
	}

	return nil
}

func (store *postgresMetadataStore) DocumentVersionInfo(ctx context.Context, docID uu.ID, version docdb.VersionTime) (*docdb.VersionInfo, error) {
	records, err := db.QueryStructSlice[docVersionQueryResult](
		ctx,
		/* sql */ `
		select *
		from docdb.document_version dv
		join docdb.document_version_file dvf on dv.id = dvf.document_version_id
		where document_id = $1 and version = $2`,
		docID,
		version,
	)

	if err != nil {
		return nil, err
	}

	if len(records) == 0 {
		return nil, sql.ErrNoRows
	}

	files := map[string]docdb.FileInfo{}
	for _, rec := range records {
		files[rec.Name] = docdb.FileInfo{
			Name: rec.Name,
			Size: rec.Size,
			Hash: rec.Hash,
		}
	}

	firstRec := records[0]
	result := &docdb.VersionInfo{
		CompanyID:     firstRec.ClientCompanyID,
		DocID:         firstRec.DocumentID,
		Version:       firstRec.Version,
		PrevVersion:   *firstRec.PrevVersion,
		CommitUserID:  firstRec.CommitUserID,
		CommitReason:  firstRec.CommitReason,
		AddedFiles:    firstRec.AddedFiles,
		ModifiedFiles: firstRec.ModifiedFiles,
		RemovedFiles:  firstRec.RemovedFiles,
		Files:         files,
	}

	return result, nil
}

func (store *postgresMetadataStore) LatestDocumentVersionInfo(ctx context.Context, docID uu.ID) (*docdb.VersionInfo, error) {
	records, err := db.QueryStructSlice[docVersionQueryResult](
		ctx,
		/* sql */ `
		select *
		from docdb.document_version dv
		join docdb.document_version_file dvf on dv.id = dvf.document_version_id
		where document_id = $1 and dv.version = (
			select version
			from docdb.document_version
			where document_id = $1
			order by version desc
			limit 1
		)`,
		docID,
	)

	if err != nil {
		return nil, err
	}

	if len(records) == 0 {
		return nil, sql.ErrNoRows
	}

	files := map[string]docdb.FileInfo{}
	for _, rec := range records {
		files[rec.Name] = docdb.FileInfo{
			Name: rec.Name,
			Size: rec.Size,
			Hash: rec.Hash,
		}
	}

	firstRec := records[0]
	result := &docdb.VersionInfo{
		CompanyID:     firstRec.ClientCompanyID,
		DocID:         firstRec.DocumentID,
		Version:       firstRec.Version,
		PrevVersion:   *firstRec.PrevVersion,
		CommitUserID:  firstRec.CommitUserID,
		CommitReason:  firstRec.CommitReason,
		AddedFiles:    firstRec.AddedFiles,
		ModifiedFiles: firstRec.ModifiedFiles,
		RemovedFiles:  firstRec.RemovedFiles,
		Files:         files,
	}

	return result, nil
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

type docVersionQueryResult struct {
	DocumentVersion
	DocumentVersionFile
}
