\echo
\echo '=== current.sql ==='
\echo 'INFO: check out the `./cmd/domonda-graphql/plugins/CurrentPlugin.ts`'
\echo

---- how to impersonate in PSQL ----
-- set current.user_type to '<user-type>';
-- set current.user_id to '<user-id>';
-- (optionally select a client) set current.client_company_id to '<client-company-id>';
-- set role to domonda_user;

---- user ----

create function private.current_user_id()
returns uuid as
$$
begin
  return nullif(current_setting('current.user_id', true), '')::uuid;
end;
$$
language plpgsql stable
cost 100000;

create function private.current_user_super()
returns boolean as
$$
begin
  return nullif(current_setting('current.user_type', true), '') = 'SUPER_ADMIN'
  or nullif(current_setting('current.user_type', true), '') = 'SYSTEM';
end;
$$
language plpgsql stable
cost 100000;

create function private.current_user()
returns public.user as
$$
declare
  curr_usr public.user;
begin
  select * into curr_usr from public.user where (id = private.current_user_id());
  return curr_usr;
end;
$$
language plpgsql stable
cost 100000;

create function private.current_user_language()
returns public.language_code as
$$
declare
  curr_usr_lang public.language_code;
begin
  select "language" into curr_usr_lang from public.user where (id = private.current_user_id());
  return curr_usr_lang;
end;
$$
language plpgsql stable
cost 100000;

create function public.current_user_is_wg()
returns boolean as
$$
begin
  case current_user
    when 'domonda_wg_user' then return true;
    when 'domonda_user' then return false;
    -- necessery for proper readings for the server in public.document_sorted_history
    when 'postgres' then return false;
    else return null;
  end case;
end;
$$
language plpgsql stable
cost 100000;
comment on function public.current_user_is_wg is 'Checks whether the `currentUser` is a WG (Work Group) user. Returns `null` if not authenticated.';

----

create function public.user_is_current_user(
    "user" public.user
) returns boolean as $$
    select coalesce("user".id = private.current_user_id(), false)
$$ language sql stable
cost 100000;

comment on function public.user_is_current_user is '@notNull';
