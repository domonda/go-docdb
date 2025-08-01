CREATE FUNCTION public.filter_money_transactions(
    client_company_id uuid,
    money_account_id  uuid = null,
    "type"            public.money_transaction_type = null,
    min_amount        float8 = null,
    max_amount        float8 = null,
    from_date         date = null,
    until_date        date = null,
    min_matched_count int = null,
    max_matched_count int = null,
    search_text       text = null
) RETURNS SETOF public.money_transaction AS
$$
    SELECT mt.* FROM (
        (
            SELECT mt.* FROM public.money_transaction AS mt
                INNER JOIN public.money_account AS ma ON (
                    ma.id = mt.account_id
                ) AND (
                    ma.client_company_id = filter_money_transactions.client_company_id
                )
            WHERE (COALESCE(TRIM(filter_money_transactions.search_text), '') <> '') AND (
                mt.partner_name ILIKE '%' || filter_money_transactions.search_text || '%'
            )
        ) UNION (
            SELECT mt.* FROM public.money_transaction AS mt
                INNER JOIN public.money_account AS ma ON (
                    ma.id = mt.account_id
                ) AND (
                    ma.client_company_id = filter_money_transactions.client_company_id
                )
            WHERE (COALESCE(TRIM(filter_money_transactions.search_text), '') <> '') AND (
                mt.purpose ILIKE '%' || filter_money_transactions.search_text || '%'
            )
        ) UNION (
            SELECT mt.* FROM public.money_transaction AS mt
                INNER JOIN public.money_account AS ma ON (
                    ma.id = mt.account_id
                ) AND (
                    ma.client_company_id = filter_money_transactions.client_company_id
                )
            WHERE (public.to_numeric(filter_money_transactions.search_text) IS NOT NULL) AND (
                (
                    mt.amount < (public.to_numeric(filter_money_transactions.search_text) + (public.to_numeric(filter_money_transactions.search_text) * 0.1))
                ) AND (
                    mt.amount > (public.to_numeric(filter_money_transactions.search_text) - (public.to_numeric(filter_money_transactions.search_text) * 0.1))
                )
            )
        ) UNION (
            SELECT mt.* FROM public.money_transaction AS mt
                INNER JOIN public.money_account AS ma ON (
                    ma.id = mt.account_id
                ) AND (
                    ma.client_company_id = filter_money_transactions.client_company_id
                )
            WHERE (COALESCE(TRIM(filter_money_transactions.search_text), '') = '')
        )
    ) AS mt
        INNER JOIN public.money_account AS ma ON (
            ma.id = mt.account_id
        ) AND (
            ma.client_company_id = filter_money_transactions.client_company_id
        )
    WHERE (
        (filter_money_transactions.money_account_id IS NULL) OR (
            ma.id = filter_money_transactions.money_account_id
        )
    ) AND (
        (filter_money_transactions."type" IS NULL) OR (
            mt."type" = filter_money_transactions."type"
        )
    ) AND (
        (filter_money_transactions.min_amount IS NULL) OR (
            mt.amount >= filter_money_transactions.min_amount
        )
    ) AND (
        (filter_money_transactions.max_amount IS NULL) OR (
            mt.amount <= filter_money_transactions.max_amount
        )
    ) AND (
        (filter_money_transactions.from_date IS NULL) OR (
            mt.booking_date >= filter_money_transactions.from_date
        )
    ) AND (
        (filter_money_transactions.until_date IS NULL) OR (
            mt.booking_date <= filter_money_transactions.until_date
        )
    ) AND (
        (filter_money_transactions.min_matched_count IS NULL) OR (
            filter_money_transactions.min_matched_count <= COALESCE(
                (SELECT SUM(1) FROM public.document_money_transaction AS dmt WHERE (dmt.money_transaction_id = mt.id)),
                0
            )
        )
    ) AND (
        (filter_money_transactions.max_matched_count IS NULL) OR (
            filter_money_transactions.max_matched_count >= COALESCE(
                (SELECT SUM(1) FROM public.document_money_transaction AS dmt WHERE (dmt.money_transaction_id = mt.id)),
                0
            )
        )
    )
    ORDER BY mt.booking_date DESC
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION public.filter_money_transactions IS 'Returns filtered `MoneyTransactions` a `Company`. Function arguments except `companyId` that are NULL are not used for filtering.';

----

CREATE TYPE public.money_transactions_statistics AS (
  incoming_sum float8,
  outgoing_sum float8
);
COMMENT ON COLUMN public.money_transactions_statistics.incoming_sum IS '@notNull';
COMMENT ON COLUMN public.money_transactions_statistics.outgoing_sum IS '@notNull';
COMMENT ON TYPE public.money_transactions_statistics IS 'Statistics about the money transactions mirroring the `filterMoneyTransactions` function.';

CREATE FUNCTION public.filter_money_transactions_statistics(
    client_company_id uuid,
    money_account_id  uuid = null,
    "type"            public.money_transaction_type = null,
    min_amount        float8 = null,
    max_amount        float8 = null,
    from_date         date = null,
    until_date        date = null,
    min_matched_count int = null,
    max_matched_count int = null,
    search_text       text = null
) RETURNS public.money_transactions_statistics AS
$$
    SELECT
        SUM(CASE "type" WHEN 'INCOMING' THEN amount ELSE 0 END), -- incoming sum
        SUM(CASE "type" WHEN 'OUTGOING' THEN amount ELSE 0 END) -- outgoing sum
    FROM public.filter_money_transactions(
        filter_money_transactions_statistics.client_company_id,
        filter_money_transactions_statistics.money_account_id,
        filter_money_transactions_statistics."type",
        filter_money_transactions_statistics.min_amount,
        filter_money_transactions_statistics.max_amount,
        filter_money_transactions_statistics.from_date,
        filter_money_transactions_statistics.until_date,
        filter_money_transactions_statistics.min_matched_count,
        filter_money_transactions_statistics.max_matched_count,
        filter_money_transactions_statistics.search_text
    )
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION public.filter_money_transactions_statistics IS 'Statistics about the results of `filterOpenItems`.';
