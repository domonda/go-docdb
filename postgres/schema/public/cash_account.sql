CREATE TABLE public.cash_account (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    client_company_id uuid NOT NULL REFERENCES public.client_company(company_id) ON DELETE CASCADE,

    "number" text NOT NULL CHECK(length(name) > 0),
    unique(client_company_id, "number"),

    name text NOT NULL CHECK(length(name) > 0),

    currency currency_code NOT NULL,
    balance  float8,

    balance_at_date date,
    constraint balance_must_be_present_for_balance_at_date check(
        case
            when balance_at_date is not null
            then balance is not null
            else true
        end
    ),

    address text,

    general_ledger_account_id uuid references public.general_ledger_account(id),
    unique(client_company_id, general_ledger_account_id),

    active bool not null default true,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.cash_account TO domonda_user;
grant select on table public.cash_account to domonda_wg_user;

create index cash_account_client_company_id_idx on public.cash_account (client_company_id);

----

create function public.cash_account_full_name(
    cash_account public.cash_account
) returns text as $$
    select cash_account.name || ' (...' || right(cash_account."number", 4) || ')'
$$ language sql immutable strict;

comment on function public.cash_account_full_name is '@notNull';

----

create function public.create_cash_account(
    client_company_id uuid,
    "number" text,
    name text,
    currency currency_code,
    active bool,
    general_ledger_account_id uuid = null,
    balance float8 = null,
    balance_at_date date = null
) returns public.cash_account as $$
    insert into public.cash_account (client_company_id, "number", name, currency, active, general_ledger_account_id, balance, balance_at_date)
    values (
        create_cash_account.client_company_id,
        create_cash_account."number",
        create_cash_account.name,
        create_cash_account.currency,
        create_cash_account.active,
        create_cash_account.general_ledger_account_id,
        create_cash_account.balance,
        create_cash_account.balance_at_date
    )
    returning *
$$ language sql volatile;

create function public.update_cash_account(
    id uuid,
    "number" text,
    name text,
    currency currency_code,
    active bool,
    general_ledger_account_id uuid = null,
    balance float8 = null,
    balance_at_date date = null
) returns public.cash_account as $$
    update public.cash_account
    set
        "number"=update_cash_account."number",
        name=update_cash_account.name,
        currency=update_cash_account.currency,
        active=update_cash_account.active,
        general_ledger_account_id=update_cash_account.general_ledger_account_id,
        balance=update_cash_account.balance,
        balance_at_date=update_cash_account.balance_at_date,
        updated_at=now()
    where id = update_cash_account.id
    returning *
$$ language sql volatile;

create function public.delete_cash_account(
    id uuid
) returns public.cash_account as $$
    delete from public.cash_account
    where id = delete_cash_account.id
    returning *
$$ language sql volatile;
