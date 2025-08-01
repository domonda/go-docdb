create type public.paypal_transaction_type as enum (
    'INCOMING',
    'OUTGOING'
);

comment on type public.paypal_transaction_type is 'Type of the `PaypalTransaction`.';

----

-- uniqueness: (account_id, transaction_code)

create table public.paypal_transaction (
    id uuid primary key default uuid_generate_v4(),

    account_id uuid not null references public.paypal_account(id) on delete cascade,

    partner_name       text,
    partner_email      text,
    partner_company_id uuid references public.partner_company(id) on delete set null,

    "type"       public.paypal_transaction_type not null,
    gross        float8,
    fee          float8,
    amount       float8 not null,
    balance      float8,
    tax          float8,
    shipping_fee float8,

    foreign_currency     currency_code not null,
    foreign_gross        float8,
    foreign_fee          float8,
    foreign_amount       float8 not null,
    foreign_balance      float8,
    foreign_tax          float8,
    foreign_shipping_fee float8,

    booking_date date not null,

    transaction_type            text, -- TODO: check if always provided
    transaction_status          text, -- TODO: check if always provided
    transaction_code            text not null unique,
    associated_transaction_code text,

    invoice_number text,

    article_name   text,
    article_number text,
    article_count  int,

    delivery_address   text,
    address_status     text,
    address            text,
    additional_address text,
    address_place      text,
    address_state      text,
    address_zip        text,
    address_country    text,
    telephone          text,

    note              text,
    subject           text,
    impact_on_balance text,

    -- NOTE: import document represents the document from which this transaction originates
    import_document_id uuid references public.document(id) on delete cascade,

    -- when in category, a transaction is considered matched (no belonging document)
    money_category_id uuid references public.money_category(id) on delete restrict,

    updated_at updated_time not null,
    created_at created_time not null,

    constraint paypal_transaction_uniqueness unique (account_id, transaction_code)
);

grant select on public.paypal_transaction to domonda_user;
grant select on table public.paypal_transaction to domonda_wg_user;
grant update (partner_company_id, updated_at) on public.paypal_transaction to domonda_user;

create index paypal_transaction_money_category_id_idx on public.paypal_transaction (money_category_id);
