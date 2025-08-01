-- public.document is referenced in the following tables, always as the document_id field:
--
-- public.bank_export_money_transaction_document
-- public.bank_payment
-- public.delivery_note
-- public.document_export_document
-- public.document_money_transaction
-- public.document_tag
-- docdb.document_version
-- public.document_workflow_step_log
-- public.email_attachment
-- public.invoice
-- public.scan_item
-- public.document_comment
--
-- And here:
-- public.document
--     supersedes uuid, -- don't contraint FK to prevent insert order problems, old doc may also been deleted  references public.document(id), -- The document ID of a document that was superseded by this one
create table public.document (
    id uuid primary key,

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    base_document_id uuid references public.document(id) on delete restrict,
    constraint derived_has_no_version check (
        base_document_id is null or (
            -- A derived document never has a version because it uses the files
            -- of the latest version of the document it was derived from.
            -- It also can't be checked out or supersede another document.
            version is null
                and checkout_user_id is null
                and checkout_reason is null
                and checkout_time is null
                and supersedes is null
        )
    ),

    type        public.document_type not null,
    category_id uuid not null references public.document_category(id),

    workflow_step_id uuid references public.document_workflow_step(id),

    imported_by uuid not null
        default public.unknown_user_id()
        references public.user(id) on delete set default,
    import_date        timestamptz not null, -- When the document was originally imported, maybe be different from created_at
    source_date        timestamptz not null, -- When the document was created at the source system
    source             text not null,        -- Name of the source system from where the document came
    source_id          text not null,        -- ID of the document within the source system from where the it came
    source_file        text not null,
    source_file_hash   text not null,

    "name"   text not null,                       -- A sanitized version of the source_file name used as filename base for downloads
    title    text check(length(trim(title)) > 0), -- A good human readable title for the document, different from name
    language language_code not null default 'de',

    version          timestamptz,     -- Checked in version of the document, NULL for a new, checked out document
    checkout_user_id uuid references public.user(id), -- A document is checked out when checkout_user_id is not NULL
    checkout_reason  text check(length(trim(checkout_reason)) > 0),
    checkout_time    timestamptz,

    superseded boolean not null default false,  -- A superseded document has one or more derived documents that supersede it
    supersedes uuid, -- don't contraint FK to prevent insert order problems, old doc may also been deleted. Was: references public.document(id), -- The document ID of a document that was superseded by this one
    archived   boolean not null default false,
    
    rearranged_at      timestamptz,     -- A document has been rearranged when the order of pages or num_attach_pages has been changed
    rearranged_by      uuid references public.user(id) on delete set null,
    pages_confirmed_at timestamptz,     -- When the doc pages are confirmed, then they won't need page separation
    pages_confirmed_by uuid references public.user(id) on delete set null,
    num_pages          int not null default 0,          -- Total number of document pages
    num_attach_pages   int not null default 0,          -- Number of pages at the end of the document which are considered as attachments
    page_images        text[]  not null default '{}',
    ocr                boolean not null default false,  -- Document was scanned
    
    custom_extraction_service public.extraction_service, -- null means no customization, use default

    -- columns EXCLUSIVELY used for fulltext search.
    -- please be careful and sanitize the text before adding
    fulltext text not null, -- full text of all document pages

    -- fulltext and document type specific metadata combined by
    -- trigger function private.document_update_fulltext_and_searchtext()
    -- TODO rename fulltext_w_invoice to fulltext_w_metadata because it's not invoice specific anymore
    fulltext_w_invoice text not null, -- auto-generated

    --TODO-db-210309 convert to a generated column after upgrading to Postgres 12
    searchtext tsvector not null, -- auto-generated

    updated_at updated_time not null,
    created_at created_time not null
);

create index document_client_company_id_idx on public.document (client_company_id);
create index document_category_id_idx on public.document (category_id);
create index document_workflow_step_id_idx on public.document (workflow_step_id);
create index document_workflow_step_id_is_null_idx on public.document ((workflow_step_id is null));
create index document_imported_by_idx on public.document (imported_by);
create index document_base_document_id_idx on public.document (base_document_id);
create index document_supersedes_idx on public.document (supersedes);
create index document_superseded_idx on public.document (superseded);
create index document_import_date_idx on public.document (import_date);
create index document_checkout_user_id_idx on public.document (checkout_user_id);
create index document_num_pages_idx on public.document (num_pages);
create index document_has_pages_idx on public.document ((num_pages > 0));
create index document_fulltext_idx on public.document using gin (fulltext gin_trgm_ops);
create index document_fulltext_w_invoice_idx on public.document using gin (fulltext_w_invoice gin_trgm_ops);
create index document_searchtext_idx on public.document using gin (searchtext);
create index document_source_idx on public.document (source);
create index document_source_id_idx on public.document (source_id);
create index document_archived_idx on public.document (archived);
create index document_client_company_id_archived_idx on public.document (client_company_id, archived);
create index document_created_at_idx on public.document (created_at);

grant select, insert, update on table public.document to domonda_user;
grant select, update on table public.document to domonda_wg_user;

----

create type public.document_statistics as (
    net_sum             float8,
    total_sum           float8,
    same_document_types boolean
);

comment on column public.document_statistics.net_sum is '@notNull';
comment on column public.document_statistics.total_sum is '@notNull';
comment on column public.document_statistics.same_document_types is '@notNull';
comment on type public.document_statistics is 'Statistics about the documents mirroring the `filterDocuments` function.';

----

create function public.document_company_by_client_company_id(
    document public.document
) returns public.company as
$$
    select * from public.company where id = document.client_company_id
$$
language sql stable;

comment on function public.document_company_by_client_company_id is '@notNull';

----

create function public.get_document(
    document_id       uuid,
    client_company_id uuid
) returns public.document as
$$
	select * from public.document where (
        id = get_document.document_id
    ) and (
        (get_document.client_company_id is null) or (
            client_company_id = get_document.client_company_id
        )
    )
    limit 1
$$
language sql stable;

comment on function public.get_document(uuid, uuid) is 'Returns a document for the specified company';
grant execute on function public.get_document(uuid, uuid) to domonda_user;

----

create function public.documents_by_ids(
    ids uuid[]
) returns setof public.document as
$$
    select * from public.document where (id = any(ids))
$$
language sql stable strict;

comment on function public.documents_by_ids is 'Returns `Documents` by their `rowId`.';

----

create function public.document_is_superseded(
    document public.document
) returns boolean as
$$
    select (
        document.superseded
    ) or (
        exists(
            select 1 from public.document as superseded_d where (superseded_d.supersedes = document.id) limit 1
        )
    )
$$
language sql stable;

comment on function public.document_is_superseded is E'@notNull\nIndicates if the `Document` is deleted or superseded by another document.';

----

create function public.document_is_derived(
    document public.document
) returns boolean as
$$
    select document_is_derived.document.base_document_id is not null
$$
language sql immutable strict;

comment on function public.document_is_derived is E'@notNull\nIndicates if the `Document` is derived from another one';

----

create function public.document_is_in_protected_workflow_step(
    document public.document
) returns boolean as $$
    select coalesce((
        document.workflow_step_id is not null
        and not exists(select from public.document_workflow_step where id = document.workflow_step_id)
    ), false)
$$ language sql stable strict;

comment on function public.document_is_in_protected_workflow_step is E'@notNull\nIs the `Document` in a protected workflow step? True only, and only, if the document **is in a workflow step but the user does not have access to it**.';

-- public.document_workflow_step_is_last_step intentionally not used - separate function favors performance
create function public.document_in_last_workflow_step(
    document public.document
) returns boolean as $$
    select document.workflow_step_id = (
        select id
        from public.document_workflow_step
        where workflow_id = (select workflow_id
            from public.document_workflow_step
            where document_workflow_step.id = document.workflow_step_id)
        order by index desc
        limit 1
    )
$$ language sql stable security definer;

comment on function public.document_in_last_workflow_step is E'Is the `Document` in the last workflow step of the workflow? Is `null` when the document has no workflow step assigned.';

----

create function public.document_is_visual(
  document public.document
) returns boolean as $$
  select document_type in (
    'INCOMING_INVOICE',
    'OUTGOING_INVOICE',
    'INCOMING_DUNNING_LETTER',
    'OUTGOING_DUNNING_LETTER',
    'INCOMING_DELIVERY_NOTE',
    'OUTGOING_DELIVERY_NOTE',
    'BANK_STATEMENT',
    'CREDITCARD_STATEMENT',
    'FACTORING_STATEMENT',
    'DMS_DOCUMENT',
    'OTHER_DOCUMENT'
  )
  from public.document_category
  where document_category.id = document.category_id
$$ language sql stable strict;
comment on function public.document_is_visual is E'@notNull\nThe `Document` is visual and is _expected_ to have pages.';

create function public.document_has_pages(
  document public.document
) returns boolean as $$
  select document.num_pages > 0
$$ language sql immutable strict;
comment on function public.document_has_pages is E'@notNull\nThe `Document` is visual and has pages.';
create function public.document_exists(id uuid)
returns boolean as $$
    select exists(select from public.document where document.id = document_exists.id)
$$ language sql stable security definer;

comment on function public.document_exists is E'@notNull\nCheck if a `Document` exists even if the user does not have access to it.';

----

create function public.set_document_archived(
    document_id uuid,
    archived    boolean
) returns public.document as $$
    update public.document
    set archived=set_document_archived.archived, updated_at=now()
    where id = set_document_archived.document_id
    returning *
$$ language sql volatile strict;

create function public.set_documents_archived(
    document_ids uuid[],
    archived     boolean
) returns setof public.document as $$
    update public.document
    set archived=set_documents_archived.archived, updated_at=now()
    where id = any(set_documents_archived.document_ids)
    returning *
$$ language sql volatile strict;

----

create function public.document_has_derived_documents(
    document public.document
) returns boolean as $$
    select exists (
        select from public.document as derived
        where derived.base_document_id = document.id)
$$ language sql stable strict;
comment on function public.document_has_derived_documents is '@notNull';

create function public.document_derived_documents(
    document public.document
) returns setof public.document as $$
    select derived.*
    from public.document as derived
    where derived.base_document_id = document.id
$$ language sql stable strict;

----

-- TODO
-- create table public.document_source (
--     document_id uuid primary key references public.document(id) on delete cascade,

--     file_format not null trimmed_text,

--     created_at timestamptz not null default now()
-- );
