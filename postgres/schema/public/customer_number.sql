-- Associates a client company with a customer number used for automatic
-- invoice creation.
CREATE TABLE public.customer_number (
    client_company_id uuid PRIMARY KEY REFERENCES public.client_company(company_id) ON DELETE CASCADE,
    customer_number text NOT NULL,
    year int NOT NULL,
    num int NOT NULL
);