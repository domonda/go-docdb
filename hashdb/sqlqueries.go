package hashdb

type SQLQueries struct {
	DocumentExists       string
	AllDocumentIDs       string
	CompanyDocumentIDs   string
	DocumentCompanyID    string
	SetDocumentCompanyID string
}

var DefaultSQLQueries = SQLQueries{
	DocumentExists:       `select exists(select from public.document where id = $1)`,
	AllDocumentIDs:       `select id from public.document`,
	CompanyDocumentIDs:   `select id from public.document where client_company_id = $1`,
	DocumentCompanyID:    `select client_company_id from public.document where id = $1`,
	SetDocumentCompanyID: `update public.document set client_company_id=$2, updated_at=now() where id = $1 and client_company_id <> $2 returning true`,
}
