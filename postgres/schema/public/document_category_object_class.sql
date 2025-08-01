create table public.document_category_object_class (
    document_category_id uuid not null references public.document_category(id) on delete cascade,
    object_class_name    text not null references object.class("name") on delete restrict,
    primary key (document_category_id, object_class_name),

    min_instances int not null default 1,
    max_instances int not null default 1,
    constraint min_max_instances_check check (min_instances >= 0 and max_instances > 0 and min_instances <= max_instances),

    created_by trimmed_text not null,
    created_at timestamptz  not null default now()
);

grant all on public.document_category_object_class to domonda_user;
grant select on table public.document_category_object_class to domonda_wg_user;

create index document_category_object_class_cat_idx on public.document_category_object_class (document_category_id);
create index document_category_object_class_obj_idx on public.document_category_object_class (object_class_name);

----

-- Only objects of a class linked to the category of the document with
-- an public.document_category_object_class entry
-- are supposed to be linked to a document of the linked category.
create table public.document_object_instance (
    id uuid primary key default uuid_generate_v4(),

    document_id        uuid not null references public.document(id) on delete cascade,
    object_instance_id uuid not null references object.instance(id) on delete cascade,

    created_by trimmed_text not null,
    created_at timestamptz  not null default now()
);

grant all on public.document_object_instance to domonda_user;
grant select on table public.document_object_instance to domonda_wg_user;

create index document_object_instance_document_id_idx on public.document_object_instance (document_id);
create index document_object_instance_object_instance_id_idx on public.document_object_instance (object_instance_id);