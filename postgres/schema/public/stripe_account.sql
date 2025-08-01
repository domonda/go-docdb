CREATE TABLE public.stripe_account (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    client_company_id uuid NOT NULL REFERENCES public.client_company(company_id) ON DELETE CASCADE,
    internal_id       text NOT NULL CHECK(length(internal_id) > 0),
    UNIQUE(client_company_id, internal_id),

    name text NOT NULL CHECK(length(name) > 0),

    currency currency_code NOT NULL,
    balance  float8,

    general_ledger_account_id uuid references public.general_ledger_account(id),
    unique(client_company_id, general_ledger_account_id),

    active bool not null default true,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.stripe_account TO domonda_user;
grant select on table public.stripe_account to domonda_wg_user;
