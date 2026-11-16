-- One row per correction CreateDocumentVersion made to the stored record of a
-- version under docdb.ContextWithFileContentWinsOverVersionInfo: what the
-- version's file records and delta lists held before, and what replaced them.
--
-- The row is written by the same statement as the correction it records, so it
-- exists exactly when the correction does. A log line cannot give that: it is
-- written outside the transaction, and claims a correction an outer rollback
-- undid or misses one whose commit failed to be acknowledged. The values it
-- keeps are otherwise lost, because the source store they were mirrored from is
-- the one the migration exists to retire.
--
-- Cascaded with the version, like the version's file records: it describes that
-- record, and is not kept for a version that is gone.
create table docdb.document_version_correction (
    id                  uuid primary key,
    document_version_id uuid not null references docdb.document_version (id) on delete cascade,
    corrected_at        timestamptz not null default now(),

    -- The files whose size and hash were rewritten, with the size and hash each
    -- had before and after, as parallel arrays: element i of every array
    -- describes corrected_files[i]. Empty for a correction of the delta lists
    -- alone, which is a version whose own file records were right while its
    -- delta lists still described the stale hashes of its predecessor.
    corrected_files text[]   not null,
    old_sizes       bigint[] not null,
    old_hashes      text[]   not null,
    new_sizes       bigint[] not null,
    new_hashes      text[]   not null,
    check (
        cardinality(old_sizes) = cardinality(corrected_files) and
        cardinality(old_hashes) = cardinality(corrected_files) and
        cardinality(new_sizes) = cardinality(corrected_files) and
        cardinality(new_hashes) = cardinality(corrected_files)
    ),

    -- The delta lists before and after. Derived from the file hashes, they are
    -- rewritten by every correction, so every row has them.
    old_added_files    text[],
    old_removed_files  text[],
    old_modified_files text[],
    new_added_files    text[],
    new_removed_files  text[],
    new_modified_files text[]
);

create index document_version_correction_document_version_id_idx
    on docdb.document_version_correction (document_version_id);

comment on table docdb.document_version_correction is 'What correcting a stored version record to its file content overwrote';
