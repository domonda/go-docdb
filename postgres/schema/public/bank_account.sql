create type public.bank_account_type as enum (
    'CURRENT',
    'SAVINGS'
);

comment on type public.bank_account_type is 'Type of the `BankAccount`.';

----

create table public.bank_account (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    bank_bic       bank_bic  not null references public.bank(bic) on delete restrict,
    iban           bank_iban not null unique,
    account_number trimmed_text,
    "type"         public.bank_account_type not null,

    name        trimmed_text,
    holder      trimmed_text not null,
    description trimmed_text,

    currency  currency_code not null default 'EUR',
    available float8,
    "limit"   float8,
    balance   float8,

    general_ledger_account_id uuid references public.general_ledger_account(id),
    unique(client_company_id, general_ledger_account_id),

    xs2a_account_id text unique references xs2a.account(id) on delete set null,

    active                      bool not null default true,
    include_holder_with_payment bool not null default true,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select, insert, update, delete on table public.bank_account to domonda_user;
grant select on table public.bank_account to domonda_wg_user;

create index bank_account_client_company_id_idx on public.bank_account (client_company_id);

----

create function public.bank_account_full_name(
    bank_account public.bank_account
) returns text as
$$
    select coalesce(bank_account.name, bank_account.description, bank_account.holder) || ' (...' || right(bank_account.iban, 4) || ')'
$$
language sql immutable strict;

comment on function public.bank_account_full_name is '@notNull';

----

create function public.bank_account_can_delete(
    bank_account public.bank_account
) returns boolean as
$$
    select (bank_account.xs2a_account_id is null)
$$
language sql stable;

comment on function public.bank_account_can_delete is '@notNull';

----

create function public.create_bank_account(
    client_company_id           uuid,
    bank_bic                    bank_bic,
    iban                        bank_iban,
    "type"                      public.bank_account_type,
    holder                      text,
    currency                    currency_code,
    name                        text = null,
    description                 text = null,
    account_number              text = null,
    available                   float8 = null,
    "limit"                     float8 = null,
    balance                     float8 = null,
    general_ledger_account_id   uuid = null,
    active                      boolean = null,
    include_holder_with_payment boolean = null
) returns public.bank_account as
$$
    insert into public.bank_account (
        client_company_id,
        bank_bic,
        iban,
        "type",
        holder,
        currency,
        name,
        description,
        account_number,
        available,
        "limit",
        balance,
        general_ledger_account_id,
        active,
        include_holder_with_payment
    ) values (
        create_bank_account.client_company_id,
        create_bank_account.bank_bic,
        create_bank_account.iban,
        create_bank_account."type",
        create_bank_account.holder,
        create_bank_account.currency,
        create_bank_account.name,
        create_bank_account.description,
        create_bank_account.account_number,
        create_bank_account.available,
        create_bank_account."limit",
        create_bank_account.balance,
        create_bank_account.general_ledger_account_id,
        create_bank_account.active,
        create_bank_account.include_holder_with_payment
    ) returning *
$$
language sql volatile;

comment on function public.create_bank_account is '@notNull';

----

create function public.update_bank_account(
    id                          uuid,
    bank_bic                    bank_bic,
    iban                        bank_iban,
    "type"                      public.bank_account_type,
    holder                      text,
    currency                    currency_code,
    name                        text = null,
    description                 text = null,
    account_number              text = null,
    available                   float8 = null,
    "limit"                     float8 = null,
    balance                     float8 = null,
    general_ledger_account_id   uuid = null,
    active                      boolean = null,
    include_holder_with_payment boolean = null
) returns public.bank_account as
$$
    update public.bank_account set
        bank_bic=update_bank_account.bank_bic,
        iban=update_bank_account.iban,
        "type"=update_bank_account."type",
        holder=update_bank_account.holder,
        currency=update_bank_account.currency,
        name=update_bank_account.name,
        description=update_bank_account.description,
        account_number=update_bank_account.account_number,
        available=update_bank_account.available,
        "limit"=update_bank_account."limit",
        balance=update_bank_account.balance,
        general_ledger_account_id=update_bank_account.general_ledger_account_id,
        active=update_bank_account.active,
        include_holder_with_payment=update_bank_account.include_holder_with_payment,
        updated_at=now()
    where id = update_bank_account.id
    returning *
$$
language sql volatile;

comment on function public.update_bank_account is '@notNull';

----

create function public.delete_bank_account(
    id uuid
) returns public.bank_account as
$$
    delete from public.bank_account
    where id = delete_bank_account.id
    returning *
$$
language sql volatile security definer;

comment on function public.delete_bank_account is '@notNull';
