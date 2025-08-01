CREATE TYPE public.document_workflow_trigger AS ENUM (
    'IMPORT',            -- all imports
    'USER_UPLOAD',       -- when user uploads
    'USER_SCAN',
    'FILESYSTEM_IMPORT', -- when retrieved from cloud drive
    'EMAIL_IMPORT'       -- when imported through e-mail
);

COMMENT ON TYPE public.document_workflow_trigger IS 'Document workflow trigger. Defines on which document event will the workflow be initialized';

----

CREATE TABLE public.document_workflow (
    id                uuid PRIMARY KEY,
    client_company_id uuid REFERENCES public.client_company(company_id) ON DELETE CASCADE,

    name text NOT NULL,
    constraint client_company_name_uniqueness unique(client_company_id, name),

    -- used when the workflow cannot be manually pushed through steps (done through rules)
    is_automatic boolean not null default false,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.document_workflow TO domonda_user;
grant select on public.document_workflow to domonda_wg_user;

create index document_workflow_name_idx on public.document_workflow using gin (name gin_trgm_ops);
CREATE INDEX document_workflow_client_company_id_idx ON public.document_workflow (client_company_id);

----

CREATE FUNCTION public.create_document_workflow(
    client_company_id uuid,
    name              text,
    is_automatic      boolean = false
) RETURNS public.document_workflow AS
$$
    INSERT INTO public.document_workflow (id, client_company_id, name, is_automatic)
        VALUES (uuid_generate_v4(), create_document_workflow.client_company_id, create_document_workflow.name, create_document_workflow.is_automatic)
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;

----

CREATE FUNCTION public.update_document_workflow(
    id           uuid,
    name         text,
    is_automatic boolean = false
) RETURNS public.document_workflow AS
$$
    UPDATE public.document_workflow
        SET
            name=update_document_workflow.name,
            is_automatic=update_document_workflow.is_automatic,
            updated_at=now()
    WHERE id = update_document_workflow.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;

----

CREATE FUNCTION public.delete_document_workflow(
    id uuid
) RETURNS public.document_workflow AS
$$
    DELETE FROM public.document_workflow WHERE id = delete_document_workflow.id RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;
