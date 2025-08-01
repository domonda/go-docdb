CREATE TABLE control.document_workflow_access (
    id                      uuid PRIMARY KEY,
    client_company_user_id	uuid NOT NULL REFERENCES control.client_company_user(id) ON DELETE CASCADE,

    document_workflow_id uuid REFERENCES public.document_workflow(id) ON DELETE CASCADE,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

CREATE UNIQUE INDEX document_workflow_access_unique ON control.document_workflow_access (client_company_user_id, document_workflow_id);
CREATE UNIQUE INDEX document_workflow_access_unique_null ON control.document_workflow_access (client_company_user_id) WHERE (document_workflow_id IS NULL);

create index document_workflow_access_client_company_user_id_idx on control.document_workflow_access (client_company_user_id);
create index document_workflow_access_document_workflow_id_idx on control.document_workflow_access (document_workflow_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE control.document_workflow_access TO domonda_user;
GRANT SELECT ON TABLE control.document_workflow_access TO domonda_wg_user;

----

CREATE FUNCTION control.create_document_workflow_access(
    client_company_user_id uuid,
    document_workflow_id   uuid = NULL
) RETURNS control.document_workflow_access AS
$$
    INSERT INTO control.document_workflow_access (id, client_company_user_id, document_workflow_id)
        VALUES (
            uuid_generate_v4(),
            create_document_workflow_access.client_company_user_id,
            create_document_workflow_access.document_workflow_id
        )
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION control.update_document_workflow_access(
    id                   uuid,
    document_workflow_id uuid = NULL
) RETURNS control.document_workflow_access AS
$$
    UPDATE control.document_workflow_access
        SET
            document_workflow_id=update_document_workflow_access.document_workflow_id,
            updated_at=now()
    WHERE id = update_document_workflow_access.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION control.delete_document_workflow_access(
    id uuid
) RETURNS control.document_workflow_access AS
$$
    DELETE FROM control.document_workflow_access
    WHERE id = delete_document_workflow_access.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;
