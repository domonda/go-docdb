-- Represents a package that can be booked by a client company.
-- Customers of Domonda can have individual packages and accounting companies
-- offer 
CREATE TABLE public.payment_package (
    client_company_id     uuid PRIMARY KEY REFERENCES public.client_company(company_id) ON DELETE CASCADE,
    price                 float8,
    invoice_price         float8 NOT NULL,
    user_price            float8 NOT NULL,
    accountant_user_price float8,
    invoices_included     int,
    users_included        int
);
 