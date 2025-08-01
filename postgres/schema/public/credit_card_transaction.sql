CREATE TYPE public.credit_card_transaction_type AS ENUM (
    'INCOMING',
    'OUTGOING'
);

COMMENT ON TYPE public.credit_card_transaction_type IS 'Type of the `CreditCardTransaction`.';

----

-- uniqueness: (account_id, "type", amount, reference, booking_date)

CREATE TABLE public.credit_card_transaction (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    account_id uuid NOT NULL REFERENCES public.credit_card_account(id) ON DELETE CASCADE,

    -- partner_name non_empty_text, 👈 not simple to change because exports and views depend on this type
    partner_name text check(length(trim(partner_name)) > 0),
    constraint partner_name_non_empty_check check(length(trim(partner_name)) > 0),

    partner_company_id uuid REFERENCES public.partner_company(id) ON DELETE SET NULL,

    "type" public.credit_card_transaction_type NOT NULL,
    fee    float8,
    tax    float8,
    amount float8 NOT NULL, -- NOTE: always the transaction amount arriving at the other account

    foreign_currency currency_code,
    foreign_amount   float8,
    CHECK ((foreign_currency IS NULL) = (foreign_amount IS NULL)),

    reference text[],
    constraint reference_validity_check check(array_position(reference, null) is null and trim(array_to_string(reference, '')) <> ''),

    booking_date date NOT NULL,
    value_date   date,

    -- NOTE: import document represents the document from which this transaction originates
    import_document_id uuid REFERENCES public.document(id) ON DELETE CASCADE,

    -- when in category, a transaction is considered matched (no belonging document)
    money_category_id uuid references public.money_category(id) on delete restrict,

    note text,
    constraint note_non_empty_check check(length(trim(note)) > 0),

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL,

    CONSTRAINT credit_card_transaction_uniqueness UNIQUE (account_id, "type", partner_name, amount, reference, booking_date)
);

CREATE INDEX credit_card_transaction_account_id_idx ON public.credit_card_transaction (account_id);
CREATE INDEX credit_card_transaction_partner_company_id_idx ON public.credit_card_transaction (partner_company_id);
CREATE INDEX credit_card_transaction_import_document_id_idx ON public.credit_card_transaction (import_document_id);
CREATE INDEX credit_card_transaction_reference_idx ON public.credit_card_transaction (reference);
CREATE INDEX credit_card_transaction_money_category_id_idx ON public.credit_card_transaction (money_category_id);

GRANT SELECT ON public.credit_card_transaction TO domonda_user;
grant select on table public.credit_card_transaction to domonda_wg_user;
grant update (partner_company_id, money_category_id, note, updated_at) on public.credit_card_transaction to domonda_user;
