CREATE VIEW api.document_workflow WITH (security_barrier) AS
    SELECT 
        dw.id,
        dw.client_company_id,
        dw.name,
        dw.updated_at,
        dw.created_at
    FROM public.document_workflow AS dw
        INNER JOIN api.client_company AS cc ON (cc.company_id = dw.client_company_id);

GRANT SELECT ON TABLE api.document_workflow TO domonda_api;

COMMENT ON COLUMN api.document_workflow.client_company_id IS '@notNull';
COMMENT ON COLUMN api.document_workflow.name IS '@notNull';
COMMENT ON VIEW api.document_workflow IS $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
A `DocumentWorkflow` is a workflow through which a `Document` passes.$$;
