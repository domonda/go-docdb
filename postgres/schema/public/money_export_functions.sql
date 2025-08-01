CREATE FUNCTION public.create_money_export(
    -- export
    booking_export boolean,
    -- what
    client_company_id     uuid,
    money_transaction_ids uuid[]
) RETURNS public.money_export AS
$$
DECLARE
    created_money_export RECORD;

    curr_money_transaction       public.money_transaction;
    curr_money_account           public.money_account;
    curr_bank_transaction        public.bank_transaction;
    curr_credit_card_transaction public.credit_card_transaction;
    curr_cash_transaction        public.cash_transaction;
    curr_paypal_transaction      public.paypal_transaction;
    curr_stripe_transaction      public.stripe_transaction;

    created_money_export_money_transaction_id uuid;
BEGIN
    IF (COALESCE(array_length(create_money_export.money_transaction_ids, 1), 0) = 0) THEN
        RAISE EXCEPTION USING MESSAGE = 'no money transactions for exporting';
    END IF;

    -- creating money_export row
    INSERT INTO public.money_export (
        client_company_id,
        user_id,
        booking_export
    )
    VALUES (
        create_money_export.client_company_id,
        private.current_user_id(),
        create_money_export.booking_export
    )
    RETURNING * INTO created_money_export;

    -- inserting money_transactions into money_export_money_transaction
    FOR curr_money_transaction IN (SELECT * FROM public.money_transaction WHERE id = ANY(create_money_export.money_transaction_ids)) LOOP

        SELECT
            * INTO curr_money_account
        FROM public.money_account WHERE id = (SELECT account_id FROM public.money_transaction WHERE id = curr_money_transaction.id);
        SELECT
            * INTO curr_bank_transaction
        FROM public.bank_transaction WHERE id = curr_money_transaction.id;
        SELECT
            * INTO curr_credit_card_transaction
        FROM public.credit_card_transaction WHERE id = curr_money_transaction.id;
        SELECT
            * INTO curr_cash_transaction
        FROM public.cash_transaction WHERE id = curr_money_transaction.id;
        SELECT
            * INTO curr_paypal_transaction
        FROM public.paypal_transaction WHERE id = curr_money_transaction.id;
        SELECT
            * INTO curr_stripe_transaction
        FROM public.stripe_transaction WHERE id = curr_money_transaction.id;

        -- NOTE: we have a CASE inside the function because null records look like so: (,,,,,) instead of NULL
        INSERT INTO public.money_export_money_transaction (
            money_export_id,
            money_account,
            money_transaction,
            bank_transaction,
            credit_card_transaction,
            cash_transaction,
            paypal_transaction,
            stripe_transaction
        ) VALUES (
            created_money_export.id,
            (CASE WHEN curr_money_account IS NULL THEN NULL ELSE curr_money_account END),
            (CASE WHEN curr_money_transaction IS NULL THEN NULL ELSE curr_money_transaction END),
            (CASE WHEN curr_bank_transaction IS NULL THEN NULL ELSE curr_bank_transaction END),
            (CASE WHEN curr_credit_card_transaction IS NULL THEN NULL ELSE curr_credit_card_transaction END),
            (CASE WHEN curr_cash_transaction IS NULL THEN NULL ELSE curr_cash_transaction END),
            (CASE WHEN curr_paypal_transaction IS NULL THEN NULL ELSE curr_paypal_transaction END),
            (CASE WHEN curr_stripe_transaction IS NULL THEN NULL ELSE curr_stripe_transaction END)
        )
        RETURNING id INTO created_money_export_money_transaction_id;

        -- if there are any, insert money_transaction - document matches
        IF EXISTS(SELECT 1 FROM public.document_money_transaction WHERE money_transaction_id = curr_money_transaction.id LIMIT 1) THEN
            INSERT INTO public.money_export_money_transaction_document (
                money_export_money_transaction_id,
                document_id,
                document_version,
                document_money_transaction,
                document_bank_transaction,
                document_credit_card_transaction,
                document_cash_transaction,
                document_paypal_transaction,
                document_stripe_transaction
            ) SELECT
                created_money_export_money_transaction_id,
                d.id,
                d.version,
                dmt,
                dbt,
                dcct,
                dct,
                dpt,
                dst
            FROM public.document AS d
                INNER JOIN (
                    public.document_money_transaction AS dmt
                    LEFT JOIN public.document_bank_transaction AS dbt ON (dbt.document_id = dmt.document_id AND dbt.bank_transaction_id = dmt.money_transaction_id)
                    LEFT JOIN public.document_credit_card_transaction AS dcct ON (dcct.document_id = dmt.document_id AND dcct.credit_card_transaction_id = dmt.money_transaction_id)
                    LEFT JOIN public.document_cash_transaction AS dct ON (dct.document_id = dmt.document_id AND dct.cash_transaction_id = dmt.money_transaction_id)
                    LEFT JOIN public.document_paypal_transaction AS dpt ON (dpt.document_id = dmt.document_id AND dpt.paypal_transaction_id = dmt.money_transaction_id)
                    LEFT JOIN public.document_stripe_transaction AS dst ON (dst.document_id = dmt.document_id AND dst.stripe_transaction_id = dmt.money_transaction_id)
                ) ON (dmt.document_id = d.id AND dmt.money_transaction_id = curr_money_transaction.id);
        END IF;

    END LOOP;

    -- TODO: what to do with booking_export flag?

    RETURN created_money_export;
END;
$$
LANGUAGE plpgsql VOLATILE STRICT;

----

CREATE FUNCTION public.create_money_export_from_filter(
    -- export
    booking_export boolean,
    -- what
    client_company_id uuid,
    -- filter
    money_account_id  uuid = NULL,
    "type"            public.money_transaction_type = NULL,
    min_amount        float8 = NULL,
    max_amount        float8 = NULL,
    from_date         date = NULL,
    until_date        date = NULL,
    min_matched_count int = NULL,
    max_matched_count int = NULL,
    search_text       text = NULL
) RETURNS public.money_export AS
$$
DECLARE
    created_money_export                      RECORD;
    curr_money_transaction                    RECORD;
    created_money_export_money_transaction_id uuid;
    money_export_money_transactions_count     int := 0;
BEGIN
    -- creating a temp table so that the filtered_money_transactions function/query is called only once
    CREATE TEMP TABLE filtered_money_transactions ON COMMIT DROP AS (
        SELECT id FROM public.filter_money_transactions(
            create_money_export_from_filter.client_company_id,
            create_money_export_from_filter.money_account_id,
            create_money_export_from_filter.type,
            create_money_export_from_filter.min_amount,
            create_money_export_from_filter.max_amount,
            create_money_export_from_filter.from_date,
            create_money_export_from_filter.until_date,
            create_money_export_from_filter.min_matched_count,
            create_money_export_from_filter.max_matched_count,
            create_money_export_from_filter.search_text
        )
    );

    -- create bank export
    SELECT
        * INTO created_money_export
    FROM public.create_money_export(
        create_money_export_from_filter.booking_export,
        create_money_export_from_filter.client_company_id,
        (SELECT array_agg(id) FROM filtered_money_transactions)
    );

    -- populate the filter arguments
    UPDATE public.money_export
        SET filter_args=json_build_object(
            'clientCompanyId', create_money_export_from_filter.client_company_id,
            'moneyAccountId', create_money_export_from_filter.money_account_id,
            'type', create_money_export_from_filter.type,
            'minAmount', create_money_export_from_filter.min_amount,
            'maxAmount', create_money_export_from_filter.max_amount,
            'fromDate', create_money_export_from_filter.from_date,
            'untilDate', create_money_export_from_filter.until_date,
            'minMatchedCount', create_money_export_from_filter.min_matched_count,
            'maxMatchedCount', create_money_export_from_filter.max_matched_count,
            'searchText', create_money_export_from_filter.search_text
        )
    WHERE (id = created_money_export.id)
    RETURNING * INTO created_money_export;

    RETURN created_money_export;
END;
$$
LANGUAGE plpgsql VOLATILE;

----

create function private.insert_money_export_transactions(
    money_export_id       uuid,
    money_transaction_ids uuid[]
) returns void as
$$
declare
    curr_money_transaction       public.money_transaction;
    curr_money_account           public.money_account;
    curr_bank_transaction        public.bank_transaction;
    curr_credit_card_transaction public.credit_card_transaction;
    curr_cash_transaction        public.cash_transaction;
    curr_paypal_transaction      public.paypal_transaction;
    curr_stripe_transaction      public.stripe_transaction;

    created_money_export_money_transaction_id uuid;
begin
    -- inserting money_transactions into money_export_money_transaction
    for curr_money_transaction in (select * from public.money_transaction where id = any(insert_money_export_transactions.money_transaction_ids)) loop

        select
            * into curr_money_account
        from public.money_account where id = (select account_id from public.money_transaction where id = curr_money_transaction.id);
        select
            * into curr_bank_transaction
        from public.bank_transaction where id = curr_money_transaction.id;
        select
            * into curr_credit_card_transaction
        from public.credit_card_transaction where id = curr_money_transaction.id;
        select
            * into curr_cash_transaction
        from public.cash_transaction where id = curr_money_transaction.id;
        select
            * into curr_paypal_transaction
        from public.paypal_transaction where id = curr_money_transaction.id;
        select
            * into curr_stripe_transaction
        from public.stripe_transaction where id = curr_money_transaction.id;

        -- note: we have a case inside the function because null records look like so: (,,,,,) instead of null
        insert into public.money_export_money_transaction (
            money_export_id,
            money_account,
            money_transaction,
            bank_transaction,
            credit_card_transaction,
            cash_transaction,
            paypal_transaction,
            stripe_transaction
        ) values (
            insert_money_export_transactions.money_export_id,
            (case when curr_money_account is null then null else curr_money_account end),
            (case when curr_money_transaction is null then null else curr_money_transaction end),
            (case when curr_bank_transaction is null then null else curr_bank_transaction end),
            (case when curr_credit_card_transaction is null then null else curr_credit_card_transaction end),
            (case when curr_cash_transaction is null then null else curr_cash_transaction end),
            (case when curr_paypal_transaction is null then null else curr_paypal_transaction end),
            (case when curr_stripe_transaction is null then null else curr_stripe_transaction end)
        )
        returning id into created_money_export_money_transaction_id;

        -- if there are any, insert money_transaction - document matches
        if exists(select 1 from public.document_money_transaction where money_transaction_id = curr_money_transaction.id limit 1) then
            insert into public.money_export_money_transaction_document (
                money_export_money_transaction_id,
                document_id,
                document_version,
                document_money_transaction,
                document_bank_transaction,
                document_credit_card_transaction,
                document_cash_transaction,
                document_paypal_transaction,
                document_stripe_transaction
            ) select
                created_money_export_money_transaction_id,
                d.id,
                coalesce(d.version, base_d.version),
                dmt,
                dbt,
                dcct,
                dct,
                dpt,
                dst
            from public.document as d
                inner join (
                    public.document_money_transaction as dmt
                    left join public.document_bank_transaction as dbt on (dbt.document_id = dmt.document_id and dbt.bank_transaction_id = dmt.money_transaction_id)
                    left join public.document_credit_card_transaction as dcct on (dcct.document_id = dmt.document_id and dcct.credit_card_transaction_id = dmt.money_transaction_id)
                    left join public.document_cash_transaction as dct on (dct.document_id = dmt.document_id and dct.cash_transaction_id = dmt.money_transaction_id)
                    left join public.document_paypal_transaction as dpt on (dpt.document_id = dmt.document_id and dpt.paypal_transaction_id = dmt.money_transaction_id)
                    left join public.document_stripe_transaction as dst on (dst.document_id = dmt.document_id and dst.stripe_transaction_id = dmt.money_transaction_id)
                ) on (dmt.document_id = d.id and dmt.money_transaction_id = curr_money_transaction.id)
                left join public.document as base_d on base_d.id = d.base_document_id;
        end if;

    end loop;

end
$$
language plpgsql volatile;
