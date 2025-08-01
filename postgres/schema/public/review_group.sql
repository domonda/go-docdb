create type public.review_group_origin as enum (
  'MANUAL',
  'UPLOAD',
  'EMAIL',
  'GET_MY_INVOICES',
  'API',
  'GROUP_SPLIT'
);

create table public.review_group (
  id uuid primary key default uuid_generate_v4(),

  origin public.review_group_origin not null,

  client_company_id uuid not null references public.client_company(company_id) on delete cascade,
  created_by        uuid not null references public.user(id) on delete restrict,
  updated_by        uuid not null references public.user(id) on delete restrict,

  -- locking the group itself for editing is different from document locking
  locked_by   uuid references public.user(id) on delete restrict,
  locked_at   timestamptz,
  -- group lock fields have to be null or set at the same time, except for optional locked_until
  constraint locked_check check((locked_by is null) = (locked_at is null)),

  -- the group lock can have an optional timeout deadline
  locked_until timestamptz check((locked_until is null) or (locked_by is not null)),

  processing_started_at timestamptz, -- not null means its queued for processing, needs processing_percentage not null to indicate actual processing
  processing_ended_at   timestamptz, -- processing completed, with or without an error
  processing_percentage int check(processing_percentage >= 0 and processing_percentage <= 100), -- null means actual processing has not started yet
  processing_error      text check(length(processing_error) > 0), -- user friendly error message during processing
  -- processing ended time has to exist with errors
  constraint processing_error_check check((processing_error is null) or (processing_ended_at is not null)),

  -- all documents in a group are locked via docdb.lock as long as the group exists
  documents_lock_id uuid references docdb.lock(id) on delete set null,

  updated_at updated_time not null,
  created_at created_time not null
);

grant select, update on table public.review_group to domonda_user;
grant select on table public.review_group to domonda_wg_user;

create index review_group_documents_lock_id_idx on public.review_group (documents_lock_id);
create index review_group_documents_lock_id_is_not_null_idx on public.review_group ((documents_lock_id is not null));

comment on column public.review_group.documents_lock_id is '@omit';
comment on column public.review_group.locked_until is '@omit';

----

create function public.review_group_cancelable(
  review_group public.review_group
) returns boolean as
$$
  -- only manually created review group is cancelable
  select review_group.origin = 'MANUAL'
$$
language sql immutable strict;

comment on function public.review_group_cancelable is '@notNull';

----

create function public.review_group_from_origin_created_by_in_client_company(
  origin            public.review_group_origin,
  created_by        uuid,
  client_company_id uuid
) returns public.review_group as
$$
  select * from public.review_group
  where (
    origin = review_group_from_origin_created_by_in_client_company.origin
  ) and (
    created_by = review_group_from_origin_created_by_in_client_company.created_by
  ) and (
    client_company_id = review_group_from_origin_created_by_in_client_company.client_company_id
  )
$$
language sql stable strict;
