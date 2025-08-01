create domain docdb.version_time timestamp(3) without time zone;
comment on domain docdb.version_time is 'Document version as UTC timestamp with millisecond precision';

----

create table docdb.document_version (
    id uuid primary key,

    document_id uuid not null references public.document(id) on delete cascade,
    version     docdb.version_time not null,
    unique(document_id, version),

    prev_version docdb.version_time,

    commit_user_id uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system-user ID for unknown user
        references public.user(id) on delete set default,
    commit_reason  text not null,

    added_files    text[],
    removed_files  text[],
    modified_files text[]
);

create unique index document_version_doc_ver_idx        on docdb.document_version (document_id, version);
create        index document_version_document_id_idx    on docdb.document_version (document_id);
create        index document_version_version_idx        on docdb.document_version (version);
create        index document_version_commit_user_id_idx on docdb.document_version (commit_user_id);
create        index document_version_commit_reason_idx  on docdb.document_version (commit_reason);


comment on type docdb.document_version is 'Document version meta data';
grant select on table docdb.document_version to domonda_user;


