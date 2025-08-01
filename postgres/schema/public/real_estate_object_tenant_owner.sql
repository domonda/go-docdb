create table public.real_estate_object_tenant_owner (
  id uuid primary key default uuid_generate_v4(),

  object_instance_id uuid not null references object.instance(id) on delete cascade,
  tenant_owner_id  bigint not null,
  constraint unique_object_tenant_owner unique(object_instance_id, tenant_owner_id),

  tenant_owner_no  bigint not null,
  unit_no          bigint not null,
  unit             trimmed_text not null,
  owner_link_no    bigint not null,
  owner            trimmed_text not null,

  updated_by trimmed_text not null,
  updated_at timestamptz  not null default now(),
  created_by trimmed_text not null,
  created_at timestamptz  not null default now()
);

create index object_tenant_owner_instance_id_idx on public.real_estate_object_tenant_owner(object_instance_id);

grant all on public.real_estate_object_tenant_owner to domonda_user;
grant select on table public.real_estate_object_tenant_owner to domonda_wg_user;

----

create table public.invoice_real_estate_object_tenant_owner (
  invoice_document_id    uuid not null references public.invoice(document_id) on delete cascade,
  object_tenant_owner_id uuid not null references public.real_estate_object_tenant_owner(id) on delete restrict,
  primary key(invoice_document_id, object_tenant_owner_id),

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at timestamptz  not null default now()
);

-- Only one tenant or owner per invoice
create unique index invoice_tenant_owner_idx on public.invoice_real_estate_object_tenant_owner(invoice_document_id);

grant all on public.invoice_real_estate_object_tenant_owner to domonda_user;
grant select on table public.invoice_real_estate_object_tenant_owner to domonda_wg_user;

----

create function public.real_estate_object_tenant_owners (
  real_estate_object public.real_estate_object
) returns setof public.real_estate_object_tenant_owner
language sql stable strict as $$
  select * from public.real_estate_object_tenant_owner
  where real_estate_object_tenant_owner.object_instance_id = real_estate_object.id
$$;

----

create function public.invoice_real_estate_object_tenant_owner(
  inv public.invoice
) returns public.real_estate_object_tenant_owner
language sql stable strict as $$
  select t.*
  from public.real_estate_object_tenant_owner as t
  where exists (
    select from public.invoice_real_estate_object_tenant_owner as i
    where i.object_tenant_owner_id = t.id
    and i.invoice_document_id = inv.document_id
  )
$$;

create function public.set_invoice_real_estate_object_tenant_owner(
  invoice_document_id    uuid,
  object_tenant_owner_id uuid,
  created_by             uuid = private.current_user_id()
) returns public.invoice_real_estate_object_tenant_owner
language sql volatile as $$
  insert into public.invoice_real_estate_object_tenant_owner (
    invoice_document_id,
    object_tenant_owner_id,
    created_by
  )
  values (
    set_invoice_real_estate_object_tenant_owner.invoice_document_id,
    set_invoice_real_estate_object_tenant_owner.object_tenant_owner_id,
    set_invoice_real_estate_object_tenant_owner.created_by
  )
  on conflict (invoice_document_id) do update
    set object_tenant_owner_id = excluded.object_tenant_owner_id,
      created_by = excluded.created_by,
      created_at = now()
  returning *
$$;

create function public.remove_invoice_real_estate_object_tenant_owner(
  invoice_document_id uuid
) returns public.invoice_real_estate_object_tenant_owner
language sql volatile as $$
  delete from public.invoice_real_estate_object_tenant_owner
  where invoice_document_id = remove_invoice_real_estate_object_tenant_owner.invoice_document_id
  returning *
$$;
