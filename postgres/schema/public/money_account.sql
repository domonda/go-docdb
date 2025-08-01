CREATE TYPE public.money_account_type AS ENUM (
    'BANK_ACCOUNT',
    'CREDIT_CARD_ACCOUNT',
    'CASH_ACCOUNT',
    'PAYPAL_ACCOUNT',
    'STRIPE_ACCOUNT'
);

COMMENT ON TYPE public.money_account_type IS 'Type of the `MoneyAccount`.';

----

-- public.money_account (
    -- id                uuid NOT NULL UNIQUE,
    -- client_company_id uuid NOT NULL REFERENCES public.client_company(company_id),
    -- type              public.money_account_type NOT NULL,
    -- name              text NOT NULL,
    -- external_id       text NOT NULL,
    -- UNIQUE(client_company_id, external_id),
    -- currency          currency_code NOT NULL,
    -- balance           float8,
    -- xs2a_account_id   text UNIQUE REFERENCES xs2a.account(id) ON DELETE RESTRICT,
    -- updated_at        updated_time NOT NULL,
    -- created_at        created_time NOT NULL
-- )

CREATE VIEW public.money_account AS
    (
        SELECT
            id,
            client_company_id,
            'BANK_ACCOUNT'::public.money_account_type   AS "type",
            public.bank_account_full_name(bank_account) AS "name",
            iban::text                                  AS "external_id",
            currency,
            balance,
            xs2a_account_id,
            active,
            updated_at,
            created_at
        FROM public.bank_account
    ) UNION ALL (
        SELECT
            id,
            client_company_id,
            'CREDIT_CARD_ACCOUNT'::public.money_account_type          AS "type",
            public.credit_card_account_full_name(credit_card_account) AS "name",
            "number"::text                                            AS "external_id",
            currency,
            balance,
            xs2a_account_id,
            active,
            updated_at,
            created_at
        FROM public.credit_card_account
    ) UNION ALL (
        SELECT
            id,
            client_company_id,
            'CASH_ACCOUNT'::public.money_account_type   AS "type",
            public.cash_account_full_name(cash_account) AS "name",
            "number"::text                              AS "external_id",
            currency,
            balance,
            null as xs2a_account_id,
            active,
            updated_at,
            created_at
        FROM public.cash_account
    );
    -- TODO-db-201006 add union for other account types

GRANT SELECT ON public.money_account TO domonda_user;
grant select on public.money_account to domonda_wg_user;

COMMENT ON COLUMN public.money_account.client_company_id IS '@notNull';
COMMENT ON COLUMN public.money_account."type" IS '@notNull';
COMMENT ON COLUMN public.money_account.name IS '@notNull';
COMMENT ON COLUMN public.money_account.external_id IS '@notNull';
COMMENT ON COLUMN public.money_account.currency IS '@notNull';
COMMENT ON COLUMN public.money_account.active IS '@notNull';
COMMENT ON COLUMN public.money_account.updated_at IS '@notNull';
COMMENT ON COLUMN public.money_account.created_at IS '@notNull';
COMMENT ON VIEW public.money_account IS $$
@primaryKey id
@foreignKey (client_company_id) references public.client_company (company_id)
@foreignKey (xs2a_account_id) references xs2a.account (id)
A `MoneyAccount` belonging to a `ClientCompany`. It abstracts over all supported forms of money related accounts (`BankAccount`, `CreditCardAccount`, `CashAccount`, `PaypalAccount` or `StripeAccount`).$$;

----

CREATE FUNCTION public.money_account_bank_account_by_id (
    money_account public.money_account
) RETURNS public.bank_account AS
$$
    SELECT * FROM public.bank_account WHERE (id = money_account.id)
$$
LANGUAGE SQL STABLE STRICT;

CREATE FUNCTION public.bank_account_money_account_by_id (
    bank_account public.bank_account
) RETURNS public.money_account AS
$$
    SELECT * FROM public.money_account WHERE (id = bank_account.id)
$$
LANGUAGE SQL STABLE STRICT;

COMMENT ON FUNCTION public.bank_account_money_account_by_id IS '@notNull';

----

CREATE FUNCTION public.money_account_credit_card_account_by_id (
    money_account public.money_account
) RETURNS public.credit_card_account AS
$$
    SELECT * FROM public.credit_card_account WHERE (id = money_account.id)
$$
LANGUAGE SQL STABLE STRICT;

CREATE FUNCTION public.credit_card_account_money_account_by_id (
    credit_card_account public.credit_card_account
) RETURNS public.money_account AS
$$
    SELECT * FROM public.money_account WHERE (id = credit_card_account.id)
$$
LANGUAGE SQL STABLE STRICT;

COMMENT ON FUNCTION public.credit_card_account_money_account_by_id IS '@notNull';

----

CREATE FUNCTION public.money_account_cash_account_by_id (
    money_account public.money_account
) RETURNS public.cash_account AS
$$
    SELECT * FROM public.cash_account WHERE (id = money_account.id)
$$
LANGUAGE SQL STABLE STRICT;

CREATE FUNCTION public.cash_account_money_account_by_id (
    cash_account public.cash_account
) RETURNS public.money_account AS
$$
    SELECT * FROM public.money_account WHERE (id = cash_account.id)
$$
LANGUAGE SQL STABLE STRICT;

COMMENT ON FUNCTION public.cash_account_money_account_by_id IS '@notNull';

----

CREATE FUNCTION public.money_account_paypal_account_by_id (
    money_account public.money_account
) RETURNS public.paypal_account AS
$$
    SELECT * FROM public.paypal_account WHERE (id = money_account.id)
$$
LANGUAGE SQL STABLE STRICT;

CREATE FUNCTION public.paypal_account_money_account_by_id (
    paypal_account public.paypal_account
) RETURNS public.money_account AS
$$
    SELECT * FROM public.money_account WHERE (id = paypal_account.id)
$$
LANGUAGE SQL STABLE STRICT;

COMMENT ON FUNCTION public.paypal_account_money_account_by_id IS '@notNull';

----

CREATE FUNCTION public.money_account_stripe_account_by_id (
    money_account public.money_account
) RETURNS public.stripe_account AS
$$
    SELECT * FROM public.stripe_account WHERE (id = money_account.id)
$$
LANGUAGE SQL STABLE STRICT;

CREATE FUNCTION public.stripe_account_money_account_by_id (
    stripe_account public.stripe_account
) RETURNS public.money_account AS
$$
    SELECT * FROM public.money_account WHERE (id = stripe_account.id)
$$
LANGUAGE SQL STABLE STRICT;

COMMENT ON FUNCTION public.stripe_account_money_account_by_id IS '@notNull';

----

create function public.money_account_general_ledger_account_id(
    money_account public.money_account
) returns uuid as $$
    select coalesce(
        (public.money_account_bank_account_by_id(money_account)).general_ledger_account_id,
        (public.money_account_credit_card_account_by_id(money_account)).general_ledger_account_id,
        (public.money_account_cash_account_by_id(money_account)).general_ledger_account_id,
        (public.money_account_paypal_account_by_id(money_account)).general_ledger_account_id,
        (public.money_account_stripe_account_by_id(money_account)).general_ledger_account_id
    )
$$ language sql stable strict;

create function public.money_account_general_ledger_account(
    money_account public.money_account
) returns public.general_ledger_account as $$
    select * from public.general_ledger_account where id = public.money_account_general_ledger_account_id(money_account)
$$ language sql stable strict;

----

-- TODO: index on name and external_id?

CREATE FUNCTION public.filter_money_accounts(
    client_company_id uuid,
    search_text       text = NULL,
    active            boolean = NULL
) RETURNS SETOF public.money_account AS
$$
    SELECT * FROM public.money_account
    WHERE (
      client_company_id = filter_money_accounts.client_company_id
    ) AND (
        (COALESCE(TRIM(filter_money_accounts.search_text), '') = '') OR (
            (
                name ILIKE '%' || filter_money_accounts.search_text || '%'
            ) OR (
                external_id ILIKE '%' || filter_money_accounts.search_text || '%'
            )
        )
    ) AND (
        filter_money_accounts.active IS NULL
        OR (active = filter_money_accounts.active)
    )
    ORDER BY
        active DESC
$$
LANGUAGE SQL STABLE;

----

CREATE FUNCTION public.money_accounts_balance_sum(
    client_company_id uuid,
    currency          text
) RETURNS float8 AS
$$
    SELECT SUM(balance) FROM public.money_account
    WHERE (
      client_company_id = money_accounts_balance_sum.client_company_id
    ) AND (
      currency = money_accounts_balance_sum.currency
    );
$$
LANGUAGE SQL STABLE STRICT;

----

create function xs2a.account_is_linked(
  account xs2a.account
) returns boolean as $$
  select exists (select from public.money_account where xs2a_account_id = account.id)
$$ language sql stable strict;

comment on function xs2a.account_is_linked is '@notNull';

----

create function xs2a.account_money_account_by_xs2a_account_id(
  account xs2a.account
) returns public.money_account as $$
  select * from public.money_account where xs2a_account_id = account.id limit 1
$$ language sql stable strict;

-----

create function public.money_accounts_by_ids(
    ids uuid[]
) returns setof public.money_account as $$
    select * from public.money_account where id = any(ids)
$$ language sql stable strict;

----

create function public.money_account_balance_today(
    money_account public.money_account
) returns float8 as $$
    select coalesce(
        (
            select public.cash_account_balance_today(cash_account)
            from public.cash_account
            where cash_account.id = money_account.id
        ),
        money_account.balance
    )
$$ language sql stable strict;

----

create function public.money_account_balance_until(
    money_account public.money_account,
    until_date    date = null
) returns float8 as $$
    select coalesce(
        (
            select public.cash_account_balance_until(cash_account, until_date)
            from public.cash_account
            where cash_account.id = money_account.id
        ),
        money_account.balance
    )
$$ language sql stable;
