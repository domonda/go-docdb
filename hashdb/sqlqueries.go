package hashdb

type SQLQueries struct {
	// Args: (docID uu.ID) => bool
	DocumentExists string
	// Args: () => uu.ID rows
	AllDocumentIDs string
	// Args: (companyID uu.ID) => uu.ID rows
	CompanyDocumentIDs string
	// Args: (docID uu.ID) => uu.ID
	DocumentCompanyID string
	// Args: (docID, companyID uu.ID) => true if updated
	SetDocumentCompanyID string
	// Args: (docID uu.ID) => []docdb.VersionTime
	DocumentVersions string
	// Args: (docID uu.ID, version docdb.VersionTime) => (...todo...)
	DocumentVersionInfo       string
	LatestDocumentVersionInfo string
	LatestDocumentVersion     string
	DocumentVersionFileHash   string
}

var DefaultSQLQueries = SQLQueries{
	DocumentExists:     `select exists(select from public.document where id = $1)`,
	AllDocumentIDs:     `select id from public.document`,
	CompanyDocumentIDs: `select id from public.document where client_company_id = $1`,
	DocumentCompanyID:  `select client_company_id from public.document where id = $1`,
	SetDocumentCompanyID: `
		update public.document
		set client_company_id=$2, updated_at=now()
		where id = $1 and client_company_id <> $2
		returning true`,
	DocumentVersions: `select array_agg(version order by version) from public.document_version where document_id = $1`,
	DocumentVersionInfo: `
		select
			prev_version, 
			commit_user_id,
			commit_reason,
			added_files,
			removed_files,
			modified_files
		from public.document_version
		where document_id = $1 and version = $2`,
	LatestDocumentVersionInfo: `
		select
			version,
			prev_version, 
			commit_user_id,
			commit_reason,
			added_files,
			removed_files,
			modified_files
		from public.document_version
		where document_id = $1
		order by version desc
		limit 1`,
	LatestDocumentVersion: `select version from public.document_version where document_id = $1 order by version desc limit 1`,
	DocumentVersionFileHash: `
		select f.hash
		from public.document_version as v
		inner join public.document_version_file as f
			on f.document_version_id = v.id and f.name = $3
		where v.document_id = $1 and v.version = $2`,
}
