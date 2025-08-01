CREATE VIEW api.op_health_check WITH (security_barrier) AS
    SELECT
        client_company_id,
        uploaded_documents_total,
        uploaded_documents_current_month,
        last_document_upload_date,
        number_of_active_users,
        restructure_group_open_since,
        number_of_active_bank_connections,
        last_bank_update_date,
        last_payment_date
    FROM private.op_health_check
    WHERE client_company_id = (SELECT api.current_client_company_id());

GRANT SELECT ON TABLE api.op_health_check TO domonda_api;

COMMENT ON COLUMN api.op_health_check.client_company_id IS '@notNull';
COMMENT ON COLUMN api.op_health_check.uploaded_documents_total IS '@notNull';
COMMENT ON COLUMN api.op_health_check.uploaded_documents_current_month IS '@notNull';
COMMENT ON COLUMN api.op_health_check.number_of_active_users IS '@notNull';
COMMENT ON COLUMN api.op_health_check.number_of_active_bank_connections IS '@notNull';
COMMENT ON VIEW api.op_health_check IS $$
@primaryKey client_company_id
@foreignKey (client_company_id) references api.client_company (company_id)
A `opHealthCheck` provides the company''s health check data.$$;
