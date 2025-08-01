create function builder.filter_money_transactions_query(
    -- required
    client_company_id uuid,
    -- subset of filterable money transactions
    money_transaction_ids uuid[] = '{}',
    -- fulltext
    search_text text = '',
    -- accounts
    exclude_money_account_ids boolean = false,
    money_account_ids         uuid[] = '{}',
    money_account_active      boolean = null,
    -- type
    "type" public.money_transaction_type = null,
    -- date
    from_date  date = null,
    until_date date = null,
    -- amounts
    min_amount float8 = null,
    max_amount float8 = null,
    -- matched count
    min_matched_count int = null,
    max_matched_count int = null,
    -- categories
    exclude_money_category_ids boolean = false,
    money_category_ids         uuid[] = null,
    -- cash transactions
    exclude_cash_transactions boolean = false
) returns text as
$$
declare
    -- filter
    has_money_transaction_ids boolean := array_length(money_transaction_ids, 1) is not null;
    has_search_text           boolean := trim(search_text) <> '';
    numeric_search_text       numeric := public.to_numeric(trim(search_text));
    has_money_account_ids     boolean := array_length(money_account_ids, 1) is not null;
    has_money_account_active  boolean := money_account_active is not null;
    has_type                  boolean := "type" is not null;
    has_from_date             boolean := from_date is not null;
    has_until_date            boolean := until_date is not null;
    has_min_amount            boolean := min_amount is not null;
    has_max_amount            boolean := max_amount is not null;
    has_min_matched_count     boolean := min_matched_count is not null;
    has_max_matched_count     boolean := max_matched_count is not null;
    has_money_category_ids    boolean := money_category_ids is not null;

    stmt text := 'select mt.* from ';
begin

    ---- fulltext ----

    if has_search_text then

        stmt := stmt || format(
            $stmt$(
                -- TODO-db-191204 check the usability of the query without the full-text search
                -- (
                --     select mt.* from public.money_transaction as mt
                --     where (
                --         to_tsvector('german',
                --             coalesce(mt.partner_name, '') || ' ' ||
                --             coalesce(mt.partner_iban, '') || ' ' ||
                --             coalesce(mt.purpose, '') || ' ' ||
                --             public.format_money_int(mt.amount)
                --         ) @@ plainto_tsquery('german', %1$L)
                --     )
                -- ) union
                (
                    select mt.* from public.money_transaction as mt
                    where (
                        (coalesce(public.money_transaction_derived_partner_name(mt), '') || coalesce(mt.purpose, '') || coalesce(mt.note, '')) ilike '%%' || %1$L || '%%'
                    ) %2$s
                )
            ) as mt $stmt$,
            search_text, -- %1$L
            case numeric_search_text is not null when true then format(

                $stmt$or (
                    mt.amount < (%1$s + (%1$s * 0.01))
                ) and (
                    mt.amount > (%1$s - (%1$s * 0.01))
                )$stmt$,
                numeric_search_text -- %1$s

            ) end -- %2$s (amount search if the text is of numeric type)
        );

    else

        stmt := stmt || 'public.money_transaction as mt';

    end if;

    ---- joins ----

    -- money account join is always present because of the client_company_id filter
    stmt := stmt || format(
        $stmt$
            inner join public.money_account as ma on ma.id = mt.account_id
        $stmt$
    );

    ---- wheres ----

    stmt := stmt || ' where ';

    -- provided money_transaction_ids are considered filter subsets. when set, filter within
    if has_money_transaction_ids then

        stmt := stmt || format(
            $stmt$(
                mt.id = any(%1$L)
            )and$stmt$,
            money_transaction_ids -- %1$L
        );

    end if;

    -- money_account_ids
    if has_money_account_ids then

        stmt := stmt || format(
            $stmt$(
                %1$s (ma.id = any(%2$L))
            )and$stmt$,
            case exclude_money_account_ids when true then 'not' end, -- %1$s
            money_account_ids -- %2$L
        );

    end if;

    -- money_account_active
    if has_money_account_active then

        stmt := stmt || format(
            $stmt$(
                ma.active = %1$L
            )and$stmt$,
            money_account_active -- %1$L
        );

    end if;

    -- type
    if has_type then

        stmt := stmt || format(
            $stmt$(
                mt."type" = %1$L
            )and$stmt$,
            "type" -- %1$L
        );

    end if;

    -- from_date
    if has_from_date then

        stmt := stmt || format(
            $stmt$(
                mt.booking_date is not null and mt.booking_date >= %1$L
            )and$stmt$,
            from_date -- %1$L
        );

    end if;

    -- until_date
    if has_until_date then

        stmt := stmt || format(
            $stmt$(
                mt.booking_date is not null and mt.booking_date <= %1$L
            )and$stmt$,
            until_date -- %1$L
        );

    end if;

    -- min_amount
    if has_min_amount then

        stmt := stmt || format(
            $stmt$(
                abs(mt.amount) >= abs(%1$s)
            )and$stmt$,
            min_amount -- %1$s
        );

    end if;

    -- max_amount
    if has_max_amount then

        stmt := stmt || format(
            $stmt$(
                abs(mt.amount) <= abs(%1$s)
            )and$stmt$,
            max_amount -- %1$s
        );

    end if;

    -- min_matched_count
    if has_min_matched_count then

        stmt := stmt || format(
            $stmt$(
                %1$s <= coalesce(
                    (select count(1) from public.document_money_transaction as dmt where (dmt.money_transaction_id = mt.id)),
                    0
                )
            )and$stmt$,
            min_matched_count -- %1$s
        );

    end if;

    -- max_matched_count
    if has_max_matched_count then

        stmt := stmt || format(
            $stmt$(
                %1$s >= coalesce(
                    (select count(1) from public.document_money_transaction as dmt where (dmt.money_transaction_id = mt.id)),
                    0
                )
            )and$stmt$,
            max_matched_count -- %1$s
        );

    end if;

    -- money_category_ids
    if has_money_category_ids then
        if array_length(money_category_ids, 1) is not null then

            stmt := stmt || format(
                $stmt$(
                    %1$s (mt.money_category_id = any(%2$L))
                )and$stmt$,
                case exclude_money_category_ids when true then 'mt.money_category_id is null or not' end, -- %1$s
                money_category_ids -- %2$L
            );

        else

            stmt := stmt || format(
                $stmt$(
                    mt.money_category_id is %1$s null
                )and$stmt$,
                case exclude_money_category_ids when false then 'not' end -- %1$s
                -- {} and not exclude => docs with any of the specified type
                -- {} and exclude     => docs without any of the specified type
            );

        end if;
    end if;

    if exclude_cash_transactions then

        stmt := stmt || $stmt$(
            not exists (select from public.cash_transaction where id = mt.id)
        )and$stmt$;

    end if;

    -- always present `where` statement
    stmt := stmt || format(
        $stmt$(
            -- account belongs to the client company
            ma.client_company_id = %1$L
        )$stmt$,
        client_company_id -- %1$L
    );

    ---- end wheres ----

    ---- order bys ----

    stmt := stmt || ' order by '; -- prepare order by

    -- when searching for an amount sort by the closest amount
    if has_search_text and numeric_search_text is not null then

        stmt := stmt || format('abs(mt.amount - %1$s) asc, ', numeric_search_text);

    end if;

    -- always present order
    stmt := stmt || 'mt.booking_date desc';

    ---- end order bys ----

    return stmt;
end
$$
language plpgsql immutable;
