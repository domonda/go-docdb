CREATE TABLE control.document_filter (
    client_company_user_id uuid PRIMARY KEY REFERENCES control.client_company_user(id) ON DELETE CASCADE,

    has_workflow_step    bool,
    has_invoice          bool,
    has_approval_request bool CHECK(has_approval_request = true), -- makes no sense to hide documents which have approval requests for the user
 
    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

COMMENT ON COLUMN control.document_filter.has_approval_request IS 'Filter documents who have active approval requests for the current user. Blank requests fitting the user description are also considered.';

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE control.document_filter TO domonda_user;

----

CREATE FUNCTION control.upsert_document_filter(
    client_company_user_id uuid,
    has_workflow_step      bool = NULL,
    has_invoice            bool = NULL,
    has_approval_request   bool = NULL
) RETURNS control.document_filter AS
$$
    INSERT INTO control.document_filter (client_company_user_id, has_workflow_step, has_invoice, has_approval_request)
        VALUES (
            upsert_document_filter.client_company_user_id,
            upsert_document_filter.has_workflow_step,
            upsert_document_filter.has_invoice,
            upsert_document_filter.has_approval_request
        )
    ON CONFLICT (client_company_user_id) DO UPDATE
        SET
            has_workflow_step=upsert_document_filter.has_workflow_step,
            has_invoice=upsert_document_filter.has_invoice,
            has_approval_request=upsert_document_filter.has_approval_request,
            updated_at=now()
    RETURNING *
$$
LANGUAGE SQL VOLATILE;
