-- Links an object instance to a document category.
-- Implemented for SignaCompany class instances representing
-- a company of Signa that is represented by a document category
-- for uploading documents for that company without the need
-- for separate client companies per Signa company.
create table public.document_category_object_instance (
    document_category_id uuid not null references public.document_category(id) on delete cascade,
    object_instance_id   uuid not null references object.instance(id) on delete restrict,
    primary key (document_category_id, object_instance_id),

    created_by trimmed_text not null,
    created_at timestamptz  not null default now()
);

grant all on public.document_category_object_instance to domonda_user;
grant select on table public.document_category_object_instance to domonda_wg_user;

create index document_category_object_instance_cat_idx on public.document_category_object_instance (document_category_id);
create index document_category_object_instance_obj_idx on public.document_category_object_instance (object_instance_id);
