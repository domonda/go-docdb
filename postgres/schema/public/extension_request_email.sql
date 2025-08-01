create table private.extension_request_email (
  id                uuid primary key default uuid_generate_v4(),
  client_company_id uuid not null references public.client_company(company_id) on delete cascade,
  user_id           uuid not null references public.user(id) on delete cascade,
  extension_name    non_empty_text not null,
  unique(client_company_id, user_id, extension_name),
  created_at created_time not null
);
grant select on private.extension_request_email to domonda_user;

create function public.user_has_requested_extension(
  "user"            public.user,
  client_company_id uuid,
  extension_name    text
) returns boolean as $$
  select exists (select from private.extension_request_email
    where user_id = "user".id
    and client_company_id = user_has_requested_extension.client_company_id
    and extension_name = user_has_requested_extension.extension_name)
$$ language sql stable strict;
comment on function public.user_has_requested_extension is '@notNull';
