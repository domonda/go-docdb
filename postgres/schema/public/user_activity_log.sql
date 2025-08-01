create type public.user_activity_log_type as enum (
  'LOGIN',
  'LOGOUT',
  'CURRENT_CLIENT_COMPANY_CHANGE' -- deprecated
);

create table public.user_activity_log(
  id uuid primary key default uuid_generate_v4(),

  "type"  public.user_activity_log_type not null,
  user_id uuid not null references public.user(id) on delete cascade,

  payload jsonb,

  created_at created_time not null
);

grant select on table public.user_activity_log to domonda_user;

create index user_activity_log_user_id_idx on public.user_activity_log (user_id);
create index user_activity_log_type_idx on public.user_activity_log ("type");
create index user_activity_log_payload_idx on public.user_activity_log using gin (payload);
create index user_activity_log_created_at_idx on public.user_activity_log (created_at);

----

create function public.filter_user_activity_logs(
  exclude_current_user boolean = true,
  search_text          text = null,
  "type"               public.user_activity_log_type = null,
  from_time            timestamptz = null,
  until_time           timestamptz = null
) returns setof public.user_activity_log as $$
  select user_activity_log.* from public.user_activity_log
    inner join public."user" on "user".id = user_activity_log.user_id
  where ((not exclude_current_user)
    or "user".id <> private.current_user_id())
  and ((coalesce(trim(filter_user_activity_logs.search_text), '') = '')
    or (("user".email ilike '%' || filter_user_activity_logs.search_text || '%')
      or ("user".first_name ilike '%' || filter_user_activity_logs.search_text || '%')
      or ("user".last_name ilike '%' || filter_user_activity_logs.search_text || '%')))
  and (filter_user_activity_logs."type" is null
    or filter_user_activity_logs."type" = user_activity_log."type")
  and (filter_user_activity_logs.from_time is null
    or filter_user_activity_logs.from_time >= user_activity_log.created_at)
  and (filter_user_activity_logs.until_time is null
    or filter_user_activity_logs.until_time <= user_activity_log.created_at)
  order by user_activity_log.created_at desc
$$ language sql stable;

----

create function public.user_activity_log_client_company_from_payload(
  user_activity_log public.user_activity_log
) returns public.client_company as $$
  select * from public.client_company
  where (user_activity_log.payload->>'clientCompanyId') is not null
  and company_id = (user_activity_log.payload->>'clientCompanyId')::uuid
$$ language sql stable;
