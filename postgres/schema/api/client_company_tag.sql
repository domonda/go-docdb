CREATE VIEW api.client_company_tag WITH (security_barrier) AS
    SELECT
        ct.id,
        ct.client_company_id,
        ct.tag AS name, -- TODO: refactor in `public` schema
        ct.created_at
    FROM public.client_company_tag AS ct
        INNER JOIN api.client_company AS cc ON (cc.company_id = ct.client_company_id);

GRANT SELECT, INSERT, DELETE, UPDATE ON TABLE api.client_company_tag TO domonda_api;

COMMENT ON COLUMN api.client_company_tag.client_company_id IS '@notNull';
COMMENT ON COLUMN api.client_company_tag.name IS '@notNull';
COMMENT ON VIEW api.client_company_tag IS $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
A `ClientCompanyTag` belonging to a `ClientCompany`.$$;
