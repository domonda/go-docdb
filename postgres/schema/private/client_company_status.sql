create type public.client_company_status_type as enum (
    'TESTING', -- Active for testing without demo-mode functionality
    'DEMO',    -- Active in demo-mode
    'ACTIVE',
    'INACTIVE'
);

comment on type public.client_company_status_type is 'Client company state type';


create table private.client_company_status (
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    status            public.client_company_status_type not null,
    valid_from        timestamptz not null default now()
);

create index private_client_company_status_client_company_id_idx
    on private.client_company_status (client_company_id);
create index private_client_company_status_idx
    on private.client_company_status (client_company_id, status, valid_from);

grant select on table private.client_company_status to domonda_user;

----

create function public.get_client_company_status(
    client_company_id uuid
) returns public.client_company_status_type as
$$
    select coalesce(
        (
            select ccs.status
            from private.client_company_status as ccs
            where ccs.client_company_id = get_client_company_status.client_company_id
                and now() >= ccs.valid_from
            order by ccs.valid_from desc
            limit 1
        ),
        'INACTIVE'
    )
$$
language sql stable;

create function public.is_client_company_active(
    client_company_id uuid
) returns boolean as
$$
    select public.get_client_company_status(client_company_id) <> 'INACTIVE'
$$
language sql stable;

create function public.client_company_status(
    client_company public.client_company
) returns public.client_company_status_type as
$$
    select public.get_client_company_status(client_company_status.client_company.company_id)
$$
language sql stable security definer;
comment on function public.client_company_status is '@notNull';

----

create function public.client_company_active(
    client_company public.client_company
) returns boolean as
$$
    select public.client_company_status(client_company) <> 'INACTIVE'
$$
language sql stable;
comment on function public.client_company_active is '@notNull';
