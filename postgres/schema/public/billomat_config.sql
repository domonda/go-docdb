create table public.billomat_config (
    id                uuid primary key default uuid_generate_v4(),
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    billomat_id  text not null check(length(trim(billomat_id)) > 0),
    api_key      text not null check(length(trim(api_key)) > 0),
    from_date    timestamptz, -- TODO-db-201105 use `date` type because it holds just the date

    outgoing_invoices_document_category_id uuid not null references public.document_category(id) on delete restrict,
    sync_back_payments                     bool not null default false,

    created_by  uuid not null references public.user(id) on delete restrict,
	created_at  created_time not null,
    disabled_by uuid references public.user(id) on delete restrict,
    disabled_at timestamptz,
    constraint disabled_by_at check((disabled_by is null) = (disabled_at is null))
);

create index public_billomat_config_client_company_id_idx on public.billomat_config(client_company_id);
create index public_billomat_config_disabled_at_idx       on public.billomat_config(disabled_at);

grant select, update, insert on table public.billomat_config to domonda_user;

----

create function public.client_company_current_billomat_config(
    cc public.client_company
) returns public.billomat_config as
$$
    select *
    from public.billomat_config
    where client_company_id = cc.company_id
        and disabled_at is null
        and public.is_client_company_active(cc.company_id)
    order by created_at desc
    limit 1
$$
language sql stable;

comment on function public.client_company_current_billomat_config is 'Current billomat config of a client company';

grant execute on function public.client_company_current_billomat_config to domonda_user;

----

create function public.disable_client_company_billomat_config(
    client_company_id uuid,
    disabled_by       uuid = private.current_user_id()
) returns uuid as
$$
    update public.billomat_config as c
       set disabled_by=disable_client_company_billomat_config.disabled_by,
           disabled_at=now()
     where c.client_company_id = disable_client_company_billomat_config.client_company_id
       and c.disabled_at is null
 returning c.client_company_id
$$
language sql volatile;

comment on function public.disable_client_company_billomat_config is 'Disables the current billomat config of a client company';

grant execute on function public.disable_client_company_billomat_config to domonda_user;

----

create function public.set_client_company_billomat_config(
    client_company_id  uuid,
    billomat_id        text,
    api_key            text,
    outgoing_invoices_document_category_id uuid,
    sync_back_payments bool = false,
    from_date          date = null,
    created_by         uuid = private.current_user_id()
) returns public.billomat_config as
$$
    with disable_current as (
        select public.disable_client_company_billomat_config(
            set_client_company_billomat_config.client_company_id,
            set_client_company_billomat_config.created_by
        )
    )
    insert into public.billomat_config (
        client_company_id,
        billomat_id,
        api_key,
        from_date,
        outgoing_invoices_document_category_id,
        sync_back_payments,
        created_by
    ) select
        set_client_company_billomat_config.client_company_id,
        set_client_company_billomat_config.billomat_id,
        trim(set_client_company_billomat_config.api_key),
        set_client_company_billomat_config.from_date,
        set_client_company_billomat_config.outgoing_invoices_document_category_id,
        set_client_company_billomat_config.sync_back_payments,
        set_client_company_billomat_config.created_by
    from disable_current -- must select from so disable call is not optimized away
    returning *
$$
language sql volatile;

comment on function public.set_client_company_billomat_config is 'Sets the current billomat config for a client company';

grant execute on function public.set_client_company_billomat_config to domonda_user;

----

create table private.billomat_money_transaction_synced (
    document_id          uuid not null references public.document(id) on delete cascade,
    money_transaction_id uuid not null,
    primary key(document_id, money_transaction_id),

    billomat_account_id text not null check(length(billomat_account_id) > 0),
    billomat_payment_id bigint not null,

	synced_at timestamptz not null default now()
);

create index billomat_money_tx_synced_account_id_idx on private.billomat_money_transaction_synced(billomat_account_id);

----

create type private.billomat_invoice_payment_type as enum (
    'PAID',
    'NOT_PAYABLE',
    'CANCELED'
);

create table private.billomat_invoice_payment (
    document_id          uuid not null references public.document(id) on delete cascade,
    billomat_account_id  text not null check(length(billomat_account_id) > 0),
    primary key(document_id, billomat_account_id),

    billomat_invoice_id  bigint not null,
    "type"               private.billomat_invoice_payment_type not null,

	synced_at timestamptz not null default now()
);

create index billomat_invoice_payment_document_id_idx on private.billomat_invoice_payment(document_id);
