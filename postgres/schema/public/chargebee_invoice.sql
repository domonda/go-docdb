CREATE TABLE public.chargebee_invoice (
    invoice_id  uuid  NOT NULL REFERENCES public.invoice(document_id) ON DELETE CASCADE,
    chargebee_id int NOT NULL,

    PRIMARY KEY(invoice_id, chargebee_id),

    updated_at  updated_time NOT NULL,
    created_at  created_time NOT NULL
);
