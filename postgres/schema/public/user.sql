create type public.user_type as enum (
    'SUPER_ADMIN', -- A domonda super admin with the possibility to do everything
    'STANDARD',   -- User with login credentials
    'EXTERNAL',   -- User without login credentials, uses other means of authenticating (ex. a single reusable token)
    'SYSTEM'      -- Virtual user doing system jobs

    -- deprecated but running on production
    -- 'ACCOUNTANT', -- Accountants are special creatures
    -- 'CLIENT',     -- Standard domonda user
);

comment on type public.user_type is 'Type of the `User`.';

----

create function public.unknown_user_id() returns uuid
language sql immutable parallel safe as
$$
    select '08a34dc4-6e9a-4d61-b395-d123005e65d3'::uuid
$$;

comment on function public.unknown_user_id is 'ID of the special ''Unknown'' system-user.';

----

create table public.user (
    id                uuid primary key default uuid_generate_v4(),
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    "type" public.user_type not null default 'STANDARD',

    -- above all active/enabled status
    enabled boolean not null default true,
    constraint system_users_cannot_be_disabled check(enabled or ("type" <> 'SYSTEM')),

    auth0_user_id text unique
    constraint system_users_cannot_have_auth0_user_id check((auth0_user_id is null) or ("type" <> 'SYSTEM')),

    -- necessary for external users. for example: if the link gets leaked and the user wants
    -- to issue a new one in-place, without making a new user, he can just change the token itself
    -- and remove all previous sessions bound to this user
    token text unique check (length(token) > 16), -- longer = safer
    constraint system_users_cannot_have_a_token check((token is null) or ("type" <> 'SYSTEM')),
    constraint external_users_must_have_a_token check((token is not null) or ("type" <> 'EXTERNAL')),

    "language" public.language_code not null default 'de', -- TODO use public.client_company.language when creating user

    title      text          check(length(trim(title)) > 0),
    first_name text not null check(length(trim(first_name)) > 0), -- TODO: rename to just `name`
    last_name  text          check(length(trim(last_name)) > 0),  -- optional for quick user create

    email public.email_addr,
    constraint email_must_exist_for_standard_users check(("type" <> 'STANDARD') or (email is not null)),

    -- interval in days
	domonda_update_notification int not null default 0 check(
        domonda_update_notification = 0 -- disabled
        or
        domonda_update_notification = 1 -- daily
        or
        domonda_update_notification = 7 -- weekly
    ),
    document_direct_approval_request_notification boolean not null default true,
    document_group_approval_request_notification  boolean not null default true,

    created_by uuid not null default unknown_user_id() references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO: if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time not null,
    created_at created_time not null
);

comment on table public.user is 'A domonda user.';

comment on column public.user.enabled is '@omit';
comment on column public.user.auth0_user_id is '@omit';
comment on column public.user.token is '@omit';

-- inserting and deleting is done through a controlled environment
grant select, update on table public.user to domonda_user;
grant select, update on table public.user to domonda_wg_user;

create index user_client_company_id_idx on public.user (client_company_id);
create index user_type_idx on public.user ("type");
create index user_enabled_idx on public.user (enabled);
create index user_auth0_user_id_idx on public.user (auth0_user_id);
create index user_token_idx on public.user (token);
create index user_email_idx on public.user (email);

----

create function public.user_full_name(
    "user" public.user
) returns text as
$$
    select trim(coalesce("user".title || ' ', '') || coalesce("user".first_name || ' ', '') || coalesce("user".last_name, ''))
$$
language sql immutable strict;
comment on function public.user_full_name is
E'@notNull\nGenerated full name of the user in format: "`title` `firstName` `lastName`".';

create function public.user_full_name_with_company(
    "user" public.user
) returns text as
$$
    select
        public.user_full_name("user") || ' (' || public.company_brand_name_or_name(company) || ')'
    from public.company
    where company.id = "user".client_company_id
$$
language sql stable strict;
comment on function public.user_full_name_with_company is
E'@notNull\nGenerated full name of the user with his belonging company.';

create function public.user_is_standard(
    "user" public.user
) returns boolean as $$
    select "user"."type" = 'STANDARD'
        or "user"."type" = 'SUPER_ADMIN' -- is_standard is used for the UI mostly, and the super admin can be considered a standard user
    -- deprecated but is in production due to migration
    -- or "user"."type" = 'ACCOUNTANT'
    -- or "user"."type" = 'CLIENT'
$$ language sql immutable strict;
comment on function public.user_is_standard is
E'@notNull\nIs the user of `STANDARD` or of `SUPER_ADMIN` type.';

create function public.user_is_external(
    "user" public.user
) returns boolean as $$
    select "user"."type" = 'EXTERNAL'
$$ language sql immutable strict;
comment on function public.user_is_external is
E'@notNull\nIs the user of `EXTERNAL` type.';

create function public.user_is_external_public_link(
    "user" public.user
) returns boolean as $$
    select "user"."type" = 'EXTERNAL'
    and "user".email is null
$$ language sql immutable strict;
comment on function public.user_is_external_public_link is
E'@notNull\nExternal public links are users of `EXTERNAL` type that don''t have an email address.';

create function public.user_is_super_admin(
    "user" public.user
) returns boolean as $$
    select "user"."type" = 'SUPER_ADMIN'
$$ language sql immutable strict;
comment on function public.user_is_super_admin is
E'@notNull\nIs the user of `SUPER_ADMIN` type.';

create function public.user_by_email(
    email public.email_addr
) returns public.user as $$
    select * from public.user where email = user_by_email.email limit 1
$$ language sql stable strict;
