create table docdb.lock (
    id uuid primary key default uuid_generate_v4 (),
    user_id uuid not null, -- references public.user(id) on delete restrict (only in prod, here the public schema is out of scope)
    reason text not null check (length(reason) > 0),
    created_at timestamp not null
);

create index docdb_lock_user_id_idx on docdb.lock (user_id);

create index docdb_lock_reason_idx on docdb.lock (reason);

----

create table docdb.locked_document (
    -- document_id as primary key ensures a document to be locked only once
    document_id uuid primary key, -- references public.document(id) on delete restrict (only in prod, here the public schema is out of scope)
    lock_id uuid not null references docdb.lock (id) on delete cascade
);

create index docdb_locked_document_lock_id_idx on docdb.locked_document (lock_id);

----

create function docdb.is_document_locked(document_id uuid) returns boolean
language sql stable as
$$
    select exists (
        select from docdb.locked_document
        where locked_document.document_id = is_document_locked.document_id
    )
    or exists (
        -- This second check of docdb.lock should not be necessary,
        -- if the db is in a consistent state according to our lock logic.
        -- But we had bugs that introduced half locked documents
        -- where docdb.locked_document had no row for a document
        -- but the document.id was used as id for a docdb.lock row
        -- because we are using the document.id as lock.id
        -- to lock single documents.
        -- By checking for half locked documents we err on the safe side:
        select from docdb.lock where id = is_document_locked.document_id
    )
$$;

comment on function docdb.is_document_locked is 'Returns if a document is locked';

----

create function docdb.is_document_processing(document_id uuid) returns boolean
language sql stable as
$$
    select exists (
        select from docdb.locked_document
            inner join docdb.lock on lock.id = locked_document.lock_id
        where locked_document.document_id = is_document_processing.document_id
            and lock.reason = 'EXTERNAL_EXTRACTION'
    )
$$;

comment on function docdb.is_document_processing is 'Returns if a document is currently in processing';

----

create function docdb.lock_document(
    document_id uuid,
    user_id     uuid,
    reason      text
) returns docdb.lock
language sql volatile as
$$
    with docdb_lock as (
        insert into docdb.lock (id, user_id, reason)
        values (
            lock_document.document_id, -- use document_id as docdb.lock.id
            lock_document.user_id,
            lock_document.reason
        )
        returning *
    ), locked_doc as (
        insert into docdb.locked_document (document_id, lock_id)
        values (
            lock_document.document_id, -- use document_id as docdb.locked_document.lock_id
            lock_document.document_id
        )
    )
    select * from docdb_lock
$$;

comment on function docdb.lock_document is 'Locks a single document, using the document_id as lock_id';

----

create function docdb.lock_documents(
    document_ids   uuid[],
    user_id        uuid,
    reason         text
) returns docdb.lock
language sql volatile as
$$
    with docdb_lock as (
        insert into docdb.lock (user_id, reason)
        values (lock_documents.user_id, lock_documents.reason)
        returning *
    ), docs as (
        insert into docdb.locked_document (document_id, lock_id)
        values (unnest(lock_documents.document_ids), (select id from docdb_lock))
    )
    select * from docdb_lock
$$;

comment on function docdb.lock_documents is 'Locks multiple documents and returns the lock uuid';

----

create function docdb.lock_additional_documents(lock_id uuid, document_ids uuid[]) returns void
language sql volatile as
$$
    insert into docdb.locked_document (document_id, lock_id)
    values (unnest(lock_additional_documents.document_ids), lock_additional_documents.lock_id)
$$;

comment on function docdb.lock_additional_documents is 'Locks additional documents using an existing lock';

----

create function docdb.unlock(lock_id uuid) returns setof docdb.lock
language sql volatile as
$$
    delete from docdb.lock where id = lock_id
    returning *
$$;

comment on function docdb.unlock is 'Unlocks all documents locked with the passed lock ID and returns the lock that was used';

----

-- create function docdb.unlock_documents(lock_id uuid, document_ids uuid[]) returns boolean
-- language sql volatile as
-- $$
--     with del_docs as (
--         delete from docdb.locked_document as d
--             where (
--                 d.lock_id = unlock_documents.lock_id
--             ) and (
--                 d.document_id = any(unlock_documents.document_ids)
--             )
--     ), del_lock as (
--         delete from docdb.lock
--             where (
--                 id = unlock_documents.lock_id
--             ) and (
--                 not exists (
--                     select from docdb.locked_document as d where d.lock_id = unlock_documents.lock_id
--                 )
--             )
--         returning *
--     )
--     select count(*) > 0 from del_lock
-- $$;

-- comment on function docdb.unlock_documents is 'Unlocks documents locked with lock_id and returns true if the lock was deleted because no locked documents are left';