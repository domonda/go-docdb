create type public.credit_card_type as enum (
    'AMERICAN_EXPRESS',
    'DINERS_CLUB_CARTE_BLANCHE',
    'DINERS_CLUB_INTERNATIONAL',
    'DINERS_CLUB_USA_AND_CANADA',
    'DISCOVER',
    'INSTA_PAYMENT',
    'JCB',
    'MAESTRO',
    'MASTER_CARD',
    'VISA',
    'VISA_ELECTRON'
);

comment on type public.credit_card_type is 'Type of the `CreditCard`.';

----

create table public.credit_card_account (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    bank_account_id uuid references public.bank_account(id), -- note: mainly used for booking

    "number" text not null check(length("number") > 0),
    unique(client_company_id, "number"),
    "type"   public.credit_card_type not null,

    name text not null check(length(name) > 0),

    currency  currency_code not null,
    available float8,
    "limit"   float8,
    balance   float8,

    general_ledger_account_id uuid references public.general_ledger_account(id),
    unique(client_company_id, general_ledger_account_id),

    xs2a_account_id text unique references xs2a.account(id) on delete set null,

    active bool not null default true,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select, insert, update, delete on table public.credit_card_account to domonda_user;
grant select on table public.credit_card_account to domonda_wg_user;

create index credit_card_account_client_company_id_idx on public.credit_card_account (client_company_id);

----

create function public.credit_card_account_full_name(
    credit_card_account public.credit_card_account
) returns text as
$$
    select credit_card_account.name || ' (...' || right(credit_card_account."number", 4) || ')'
$$
language sql immutable strict;

comment on function public.credit_card_account_full_name is '@notNull';

----

create function public.credit_card_account_can_delete(
    credit_card_account public.credit_card_account
) returns boolean as
$$
    select (credit_card_account.xs2a_account_id is null)
$$
language sql stable;

comment on function public.credit_card_account_can_delete is '@notNull';

----

create function public.delete_credit_card_account(
    id uuid
) returns public.credit_card_account as
$$
    delete from public.credit_card_account
    where id = delete_credit_card_account.id
    returning *
$$
language sql volatile strict security definer;

comment on function public.delete_credit_card_account is E'@notNull\nDeletes the specified `CreditCardAccount`.';

----

create function public.create_credit_card_account(
    client_company_id         uuid,
    "number"                  text,
    "type"                    public.credit_card_type,
    name                      text,
    currency                  currency_code,
    available                 float8 = null,
    "limit"                   float8 = null,
    balance                   float8 = null,
    bank_account_id           uuid = null,
    general_ledger_account_id uuid = null,
    active                    boolean = null
) returns public.credit_card_account as
$$
    insert into public.credit_card_account (
        client_company_id,
        "number",
        "type",
        name,
        currency,
        available,
        "limit",
        balance,
        bank_account_id,
        general_ledger_account_id,
        active
    ) values (
        create_credit_card_account.client_company_id,
        create_credit_card_account."number",
        create_credit_card_account."type",
        create_credit_card_account.name,
        create_credit_card_account.currency,
        create_credit_card_account.available,
        create_credit_card_account."limit",
        create_credit_card_account.balance,
        create_credit_card_account.bank_account_id,
        create_credit_card_account.general_ledger_account_id,
        create_credit_card_account.active
    ) returning *
$$
language sql volatile;

comment on function public.create_credit_card_account is '@notNull';

----

create function public.update_credit_card_account(
    id                        uuid,
    "number"                  text,
    "type"                    public.credit_card_type,
    name                      text,
    currency                  currency_code,
    available                 float8 = null,
    "limit"                   float8 = null,
    balance                   float8 = null,
    bank_account_id           uuid = null,
    general_ledger_account_id uuid = null,
    active                    boolean = null
) returns public.credit_card_account as
$$
    update public.credit_card_account set
        "number"=update_credit_card_account."number",
        "type"=update_credit_card_account."type",
        name=update_credit_card_account.name,
        currency=update_credit_card_account.currency,
        available=update_credit_card_account.available,
        "limit"=update_credit_card_account."limit",
        balance=update_credit_card_account.balance,
        bank_account_id=update_credit_card_account.bank_account_id,
        general_ledger_account_id=update_credit_card_account.general_ledger_account_id,
        active=update_credit_card_account.active,
        updated_at=now()
    where id = update_credit_card_account.id
    returning *
$$
language sql volatile;

comment on function public.update_credit_card_account is '@notNull';
