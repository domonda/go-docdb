create table public.money_export (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    user_id           uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system-user ID for unknown user
        references public.user(id) on delete set default,

    filter_args json,
    until       date,

    accounting_export public.accounting_system, -- bmd/datev/dvo or null

    booking_export boolean not null default false,

    created_at created_time not null
);

create index money_export_client_company_id_idx on public.money_export (client_company_id);
create index money_export_user_id_idx on public.money_export (user_id);

grant all on table public.money_export to domonda_user;
