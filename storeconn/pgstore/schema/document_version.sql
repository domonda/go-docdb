do $$
begin
    if not exists (select from pg_type where typname = 'version_time' and typnamespace = 'docdb'::regnamespace) then
        create domain docdb.version_time timestamp(3) without time zone;
    end if;
end $$;

comment on domain docdb.version_time is 'Document version as UTC timestamp with millisecond precision';

----

create table docdb.document_version (
    id          uuid primary key,
    document_id uuid not null, -- references public.document(id) on delete cascade (only in prod, here the public schema is out of scope)
    company_id  uuid not null, -- references public.document(company_id) on delete cascade (only in prod, here the public schema is out of scope)
    version     docdb.version_time not null,
    unique (document_id, version),

    prev_version   docdb.version_time,
    commit_user_id uuid not null default '08a34dc4-6e9a-4d61-b395-d123005e65d3', -- system-user ID for unknown user
    -- references public.user(id) on delete set default (only in prod, here the public schema is out of scope)

    commit_reason  text not null,
    added_files    text[],
    removed_files  text[],
    modified_files text[]
);

create index document_version_document_id_idx on docdb.document_version (document_id);
create index document_version_version_idx on docdb.document_version (version);
create index document_version_commit_user_id_idx on docdb.document_version (commit_user_id);
create index document_version_commit_reason_idx on docdb.document_version (commit_reason);

-- A document has exactly one genesis (first) version, stored with prev_version
-- NULL. This partial unique index enforces that: a second genesis insert for the
-- same document — even with a different version timestamp — raises a unique
-- violation, which CreateDocumentVersion maps to ErrDocumentAlreadyExists. It
-- prevents a document whose metadata exists but whose blobs are absent from
-- being silently given a duplicate genesis version.
create unique index document_version_one_genesis_per_document_idx
    on docdb.document_version (document_id)
    where prev_version is null;

-- A document's versions form a linear chain, so a version has at most one
-- successor: no two versions of a document may name the same prev_version.
-- Without this, two concurrent AddDocumentVersion calls both read the same
-- latest version, both carry its file set forward, and both insert with that
-- version as prev_version — neither existing constraint stops them, because
-- their own version timestamps differ. The later row's file set is then the
-- older one plus its own change, silently dropping the other writer's. The
-- index turns that into a unique violation, which CreateDocumentVersion maps
-- to ErrDocumentChanged for the writer that lost, so the update is refused
-- instead of lost and the caller can retry from the new latest version. Rows
-- with a NULL prev_version are not constrained here — Postgres treats NULLs as
-- distinct in a unique index — which is what the genesis index above is for.
create unique index document_version_one_successor_per_version_idx
    on docdb.document_version (document_id, prev_version);

comment on table docdb.document_version is 'Document version meta data';