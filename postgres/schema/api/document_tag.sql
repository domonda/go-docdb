CREATE VIEW api.document_tag WITH (security_barrier) AS 
    SELECT 
        dt.client_company_tag_id,
        dt.document_id,
        dt.page,
        dt.pos_x,
        dt.pos_y,
        dt.updated_at,
        dt.created_at,
        cct.name
    FROM public.document_tag AS dt
        INNER JOIN api.client_company_tag AS cct ON (cct.id = dt.client_company_tag_id);

GRANT SELECT, INSERT, DELETE ON TABLE api.document_tag TO domonda_api;

COMMENT ON COLUMN api.document_tag.client_company_tag_id IS '@notNull';
COMMENT ON COLUMN api.document_tag.document_id IS '@notNull';
COMMENT ON VIEW api.document_tag IS $$
@primaryKey client_company_tag_id,document_id
@foreignKey (client_company_tag_id) references api.client_company_tag (id)
@foreignKey (document_id) references api.document (id)
A `DocumentTag` represents an assigned `CompanyTag` to a `Document`.$$;
