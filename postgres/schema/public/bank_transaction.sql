CREATE TYPE public.bank_transaction_type AS ENUM (
    'INCOMING',
    'OUTGOING'
);

COMMENT ON TYPE public.bank_transaction_type IS 'Type of the `BankTransaction`.';

----

-- uniqueness: (account_id, "type", amount, reference, booking_date)

CREATE TABLE public.bank_transaction (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    account_id uuid NOT NULL REFERENCES public.bank_account(id) ON DELETE CASCADE,

    -- TODO change to trimmed_text, 👈 not simple to change because exports and views depend on this type
    partner_name text,
    constraint partner_name_non_empty_check check(length(trim(partner_name)) > 0),

    partner_iban       bank_iban,
    partner_bic        bank_bic,
    partner_company_id uuid REFERENCES public.partner_company(id) ON DELETE SET NULL,

    "type" public.bank_transaction_type NOT NULL,
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

    tags text[],

    -- NOTE: import document represents the document from which this transaction originates
    import_document_id uuid REFERENCES public.document(id) ON DELETE CASCADE,

    -- when in category, a transaction is considered matched (no belonging document)
    money_category_id uuid references public.money_category(id) on delete restrict,

    -- TODO: add source row id on import (text)

    note text,
    constraint note_non_empty_check check(length(trim(note)) > 0),

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL,

    CONSTRAINT bank_transaction_uniqueness UNIQUE (account_id, "type", partner_name, amount, reference, booking_date)
);

CREATE INDEX bank_transaction_account_id_idx ON public.bank_transaction (account_id);
CREATE INDEX bank_transaction_partner_company_id_idx ON public.bank_transaction (partner_company_id);
CREATE INDEX bank_transaction_import_document_id_idx ON public.bank_transaction (import_document_id);
CREATE INDEX bank_transaction_reference_idx ON public.bank_transaction (reference);
CREATE INDEX bank_transaction_money_category_id_idx ON public.bank_transaction (money_category_id);

GRANT SELECT ON public.bank_transaction TO domonda_user;
grant select on table public.bank_transaction to domonda_wg_user;
grant update (partner_company_id, money_category_id, note, updated_at) on public.bank_transaction to domonda_user;
