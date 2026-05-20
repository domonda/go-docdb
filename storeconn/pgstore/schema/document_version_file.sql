create table docdb.document_version_file (
    document_version_id uuid not null references docdb.document_version (id) on delete cascade,
    name                text not null check (length(name) > 0),
    unique (document_version_id, name),

    size bigint not null check (size >= 0),
    hash text   not null check (length(hash) = 64)
);

create index document_version_file_hash_idx on docdb.document_version_file (hash);
create index document_version_file_version_id_size_idx
    on docdb.document_version_file (document_version_id) include (size);

comment on type docdb.document_version_file is 'Document version file metadata';