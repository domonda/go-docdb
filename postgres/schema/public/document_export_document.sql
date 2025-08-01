create table public.document_export_document (
    document_export_id uuid not null references public.document_export(id) on delete cascade,
    document_id        uuid not null references public.document(id),
    primary key(document_export_id, document_id),

    document_version timestamptz not null 
);

create index document_export_document_document_export_id_idx on public.document_export_document (document_export_id);
create index document_export_document_document_id_idx on public.document_export_document (document_id);

comment on table public.document_export_document is 'The documents that belong to an export';
grant select, insert on table public.document_export_document to domonda_user;
