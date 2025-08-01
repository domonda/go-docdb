CREATE TYPE public.stripe_transaction_type AS ENUM (
    'INCOMING',
    'OUTGOING'
);

COMMENT ON TYPE public.stripe_transaction_type IS 'Type of the `PaypalTransaction`.';

----

-- uniqueness: (internal_id)

CREATE TABLE public.stripe_transaction (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    account_id uuid NOT NULL REFERENCES public.stripe_account(id) ON DELETE CASCADE,

    internal_id          text NOT NULL,
    internal_card_id     text,
    internal_transfer_id text,
    internal_partner_id  text,

    partner_company_id  uuid REFERENCES public.partner_company(id) ON DELETE SET NULL,
    partner_description text,
    partner_email       text,

    booking_date date NOT NULL,

    "type"          public.stripe_transaction_type NOT NULL,
    currency        currency_code NOT NULL,
    amount          float8 NOT NULL,
    amount_refunded float8,
    fee             float8,
    tax             float8,

    foreign_currency        currency_code,
    foreign_amount          float8,
    foreign_amount_refunded float8,

    captured             boolean,
    description          text NOT NULL,
    seller_message       text,
    invoice_id           text,
    status               text,
    statement_descriptor text,

    -- NOTE: import document represents the document from which this transaction originates
    import_document_id uuid REFERENCES public.document(id) ON DELETE CASCADE,

    -- when in category, a transaction is considered matched (no belonging document)
    money_category_id uuid references public.money_category(id) on delete restrict,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL,

    CONSTRAINT stripe_transaction_uniqueness UNIQUE (internal_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.stripe_transaction TO domonda_user;
grant select on table public.stripe_transaction to domonda_wg_user;
