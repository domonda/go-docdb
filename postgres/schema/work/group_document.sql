create table work.group_document (
    group_id    uuid not null references work.group(id)      on delete cascade,
    document_id uuid not null references public.document(id) on delete cascade,
    primary key(group_id, document_id),

    added_by uuid not null references public.user(id) on delete restrict,
    added_at timestamptz not null default now()
);

-- TODO: insert and delete rights
grant select on work.group_document to domonda_wg_user;
grant select on work.group_document to domonda_user;

create index group_document_group_id_idx on work.group_document (group_id);
create index group_document_document_id_idx on work.group_document (document_id);
