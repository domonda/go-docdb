create table public.paypal_account (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    internal_id       text not null check(length(internal_id) > 0),
    unique(client_company_id, internal_id),

    name text not null check(length(name) > 0),

    currency currency_code not null,
    balance  float8,

    general_ledger_account_id uuid references public.general_ledger_account(id),
    unique(client_company_id, general_ledger_account_id),

    xs2a_account_id text unique references xs2a.account(id) on delete set null,

    active bool not null default true,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select, insert, update, delete on table public.paypal_account to domonda_user;
grant select on table public.paypal_account to domonda_wg_user;
