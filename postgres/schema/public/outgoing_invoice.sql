-- Represents an outgoing invoice to a client company that was generated through
-- the dashboard.
CREATE TABLE public.outgoing_invoice (
    -- Invoice ID (the invoice number on the invoice itself) is comprised of
    -- the leading letter 'R", the year and a sequential number.
    invoice_id text PRIMARY KEY,

    -- The year and month for which the invoice was generated.
    year int NOT NULL,
    month int NOT NULL,

    -- This number is increased for each new invoice in the given year.
    -- It starts at 0 for each year.
    invoice_nr int NOT NULL
);

CREATE TABLE public.client_company_has_outgoing_invoice (
    client_company_id uuid REFERENCES public.client_company(company_id) ON DELETE CASCADE,
    invoice_id text REFERENCES public.outgoing_invoice(invoice_id) ON DELETE CASCADE,
    PRIMARY KEY(client_company_id, invoice_id)
);