create table docdb.document_version_file (
    document_version_id uuid not null references docdb.document_version(id) on delete cascade,
    name                text not null check(length(name) > 0),
    unique(document_version_id, name),

    size bigint not null check(size >= 0),
    hash text   not null check(length(hash) = 64)
);


create unique index document_version_file_idx      on docdb.document_version_file (document_version_id, name);
create        index document_version_file_hash_idx on docdb.document_version_file (hash);

comment on type docdb.document_version_file is 'Document version file metadata';
