CREATE TABLE public.pain001 (
    id uuid PRIMARY KEY,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT SELECT, INSERT ON TABLE public.pain001 TO domonda_user;
grant select on public.pain001 to domonda_wg_user;

----

CREATE TABLE public.pain001_payment (
    id uuid PRIMARY KEY,

    pain001_id uuid NOT NULL REFERENCES public.pain001(id) ON DELETE CASCADE,

    invoice_document_id uuid REFERENCES public.invoice(document_id) ON DELETE SET NULL,

    debitor_bank_account_id uuid NOT NULL REFERENCES public.bank_account(id) ON DELETE CASCADE,

    recipient_name text NOT NULL,
    recipient_iban public.bank_iban NOT NULL,
    recipient_bic  public.bank_bic,
    execution_date date NOT NULL,

    amount   float8 NOT NULL,
    currency public.currency_code NOT NULL,

    purpose text NOT NULL,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

CREATE INDEX pain001_payment_invoice_document_id_idx ON public.pain001_payment (invoice_document_id);
CREATE INDEX pain001_payment_debitor_bank_account_id_idx ON public.pain001_payment (debitor_bank_account_id);

GRANT SELECT, INSERT ON TABLE public.pain001_payment TO domonda_user;
grant select on public.pain001_payment to domonda_wg_user;
