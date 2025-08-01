create table public.user_group (
  id uuid primary key default uuid_generate_v4(),

  client_company_id uuid not null references public.client_company(company_id) on delete cascade,

  name non_empty_text not null,

  constraint unique_name_in_client_company unique(client_company_id, name),

  -- TODO: updated_by necessary?
  updated_at updated_time not null,

  created_by uuid not null
    default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
    references public.user(id) on delete set default,
  created_at created_time not null
);

grant all on table public.user_group to domonda_user;
grant select on table public.user_group to domonda_wg_user;

create index user_group_client_company_id_idx on public.user_group (client_company_id);
create index user_group_name_idx on public.user_group using gin (name gin_trgm_ops);

create function public.create_user_group(
  client_company_id uuid,
  name non_empty_text
) returns public.user_group as $$
  insert into public.user_group (client_company_id, name, created_by)
  values (create_user_group.client_company_id, create_user_group.name, private.current_user_id())
  returning *
$$ language sql volatile strict;

create function public.update_user_group(
  id uuid,
  name non_empty_text
) returns public.user_group as $$
  update public.user_group
    set
      name=update_user_group.name,
      updated_at=now()
  where user_group.id = update_user_group.id
  returning *
$$ language sql volatile strict;

create function public.delete_user_group(
  id uuid
) returns public.user_group as $$
  delete from public.user_group
  where user_group.id = delete_user_group.id
  returning *
$$ language sql volatile strict;

----

create table public.user_group_user (
  id uuid primary key default uuid_generate_v4(),

  user_group_id uuid not null references public.user_group(id) on delete cascade,
  user_id uuid not null references public.user(id) on delete cascade,

  constraint unique_user_in_group unique(user_group_id, user_id),

  created_by uuid not null
    default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
    references public.user(id) on delete set default,
  created_at created_time not null
);

grant select, insert, delete on table public.user_group_user to domonda_user;
grant select on table public.user_group_user to domonda_wg_user;

create index user_group_user_user_group_id_idx on public.user_group_user (user_group_id);
create index user_group_user_user_id_idx on public.user_group_user (user_id);

create function public.add_user_group_user(
  user_group_id uuid,
  user_id uuid
) returns public.user_group_user as $$
  insert into public.user_group_user (user_group_id, user_id, created_by)
  values (add_user_group_user.user_group_id, add_user_group_user.user_id, private.current_user_id())
  returning *
$$ language sql volatile strict;

create function public.delete_user_group_user(
  id uuid
) returns public.user_group_user as $$
  delete from public.user_group_user
  where user_group_user.id = delete_user_group_user.id
  returning *
$$ language sql volatile strict;
