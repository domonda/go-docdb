package postgres

import (
	"context"
	"database/sql"
	"strings"
	"time"

	"github.com/domonda/go-docdb"
	"github.com/domonda/go-sqldb/db"
	"github.com/domonda/go-types/uu"
	"github.com/ungerik/go-fs"
)

func NewMetadataStore() docdb.MetadataStore {
	return &postgresMetadataStore{}
}

type postgresMetadataStore struct{}

// it's being tested via the conn
func (store *postgresMetadataStore) AddDocumentVersion(
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
	id := uu.IDv7()
	addedFilenames := namesFromFileInfos(addedFiles)
	modifiedFilenames := namesFromFileInfos(modifiedFiles)

	err := db.Exec(
		ctx,
		/* sql */ `
		insert into docdb.document_version (
			id,
			document_id,
			company_id,
			version,
			prev_version,
			commit_user_id,
			commit_reason,
			added_files,
			removed_files,
			modified_files
		) values (
			$1,
			$2,
			$3,
			$4,
			$5,
			$6,
			$7,
			$8,
			$9,
			$10
		)`,
		id,
		docID,
		companyID,
		newVersion,
		previousVersion,
		userID,
		reason,
		addedFilenames,
		removedFiles,
		modifiedFilenames,
	)

	if err != nil {
		return nil, err
	}

	versionFiles := fileInfosIntoDocumentVersionFiles(id, addedFiles, modifiedFiles)
	if err := db.InsertStructs(
		ctx,
		"docdb.document_version_file",
		versionFiles,
	); err != nil {
		return nil, err
	}

	return &docdb.VersionInfo{
		DocID:         docID,
		CompanyID:     companyID,
		Version:       newVersion,
		CommitUserID:  userID,
		CommitReason:  reason,
		AddedFiles:    addedFilenames,
		RemovedFiles:  removedFiles,
		ModifiedFiles: modifiedFilenames,
	}, nil

}

func (store *postgresMetadataStore) CreateDocument(
	ctx context.Context,
	companyID,
	docID,
	userID uu.ID,
	reason string,
	files []fs.FileReader,
) (*docdb.VersionInfo, error) {
	versionInfo := &docdb.VersionInfo{
		Version:   docdb.VersionTimeFrom(time.Now()),
		DocID:     docID,
		CompanyID: companyID,
	}

	docVersion := DocumentVersion{
		ID:         uu.IDv7(),
		DocumentID: docID,
		CompanyID:  companyID,
		Version:    versionInfo.Version,
	}

	if err := db.InsertStruct(
		ctx,
		"docdb.document_version",
		docVersion,
	); err != nil {
		return nil, err
	}

	versionFiles := []DocumentVersionFile{}

	for _, file := range files {
		versionInfo.AddedFiles = append(versionInfo.AddedFiles, file.Name())
		data, err := file.ReadAll()
		if err != nil {
			return nil, err
		}

		versionFiles = append(versionFiles, DocumentVersionFile{
			DocumentVersionID: docVersion.ID,
			Name:              file.Name(),
			Size:              file.Size(),
			Hash:              docdb.ContentHash(data),
		})
	}

	if err := db.InsertStructs(
		ctx,
		"docdb.document_version_file",
		versionFiles,
	); err != nil {
		return nil, err
	}

	return versionInfo, nil
}

func (store *postgresMetadataStore) DocumentCompanyID(ctx context.Context, docID uu.ID) (companyID uu.ID, err error) {
	return db.QueryValue[uu.ID](
		ctx,
		/* sql */ `
		select company_id from docdb.document_version
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
		set company_id = $1
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
		where company_id = $1
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
		CompanyID:     firstRec.CompanyID,
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
		CompanyID:     firstRec.CompanyID,
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

type docVersionQueryResult struct {
	DocumentVersion
	DocumentVersionFile
}

func (store *postgresMetadataStore) DeleteDocument(ctx context.Context, docID uu.ID) error {
	deletedIDs := []uu.ID{}
	err := db.QueryRows(
		ctx,
		/* sql */ `
		delete from docdb.document_version
		where document_id = $1
		returning id
		`,
		docID,
	).ScanSlice(&deletedIDs)

	if err != nil {
		return err
	}

	if len(deletedIDs) == 0 {
		return sql.ErrNoRows
	}

	return nil
}

func (store *postgresMetadataStore) DeleteDocumentVersion(
	ctx context.Context,
	docID uu.ID,
	version docdb.VersionTime,
) (
	leftVersions []docdb.VersionTime,
	hashesToDelete []string,
	err error,
) {

	res, err := db.QueryRowStruct[struct {
		DeletedIDs     int      `db:"deleted_ids"`
		LeftVersions   []string `db:"left_versions"`
		HashesToDelete []string `db:"hashes_to_delete"`
	}](
		ctx,
		/* sql */ `
		with
		left_versions as (
			select version from docdb.document_version
			where document_id = $1 and version != $2
			order by version
		),
		hashes_to_delete as (
			select hash from docdb.document_version_file dvf
			join docdb.document_version dv
				on dvf.document_version_id = dv.id
				and dv.document_id = $1
				and dv.version = $2
			order by hash
		),
		deleted_ids as (
			delete from docdb.document_version
				where document_id = $1
				and version = $2
			returning id
		)
		select
			array_agg(distinct left_versions) as left_versions,
			array_agg(distinct hashes_to_delete) as hashes_to_delete,
			count(deleted_ids) as deleted_ids
		from
			left_versions,
			hashes_to_delete,
			deleted_ids
		`,
		docID,
		version,
	)

	if err != nil {
		return nil, nil, err
	}

	if res.DeletedIDs == 0 {
		return nil, nil, sql.ErrNoRows
	}

	// array_agg unfortunately appends some characters to the records
	for _, versionStr := range res.LeftVersions {
		versionStr = strings.Trim(versionStr, "\"()")
		version, err := docdb.VersionTimeFromString(versionStr)
		if err != nil {
			return nil, nil, err
		}
		leftVersions = append(leftVersions, version)
	}

	// array_agg unfortunately appends some characters to the records
	for _, hash := range res.HashesToDelete {
		hash = strings.Trim(hash, "\"()")
		hashesToDelete = append(hashesToDelete, hash)
	}

	return leftVersions, hashesToDelete, nil
}

func namesFromFileInfos(files []*docdb.FileInfo) (names []string) {
	for _, item := range files {
		names = append(names, item.Name)
	}
	return names
}

func fileInfosIntoDocumentVersionFiles(documentVersiononID uu.ID, batches ...[]*docdb.FileInfo) (versionFiles []*DocumentVersionFile) {
	for _, items := range batches {
		for _, item := range items {
			versionFiles = append(
				versionFiles,
				&DocumentVersionFile{
					DocumentVersionID: documentVersiononID,
					Name:              item.Name,
					Hash:              item.Hash,
					Size:              item.Size,
				},
			)
		}
	}

	return versionFiles
}
