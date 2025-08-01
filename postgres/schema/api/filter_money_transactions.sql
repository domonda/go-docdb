create function api.filter_money_transactions(
    -- fulltext
    search_text text = '',
    -- accounts
    exclude_money_account_ids boolean = false,
    money_account_ids         uuid[] = '{}',
    -- type
    "type" api.money_transaction_type = null,
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
    money_category_ids         uuid[] = null
) returns setof api.money_transaction as
$$
    select
        mt.id,
        mt.account_id,
        mt.type::text::api.money_transaction_type,
        mt.partner_name,
        mt.partner_iban,
        mt.partner_company_id,
        mt.amount,
        mt.foreign_currency,
        mt.foreign_amount,
        mt.purpose,
        mt.booking_date,
        mt.value_date,
        mt.import_document_id,
        mt.money_category_id,
        mt.updated_at,
        mt.created_at
    from public.filter_money_transactions_v2(
        client_company_id=>api.current_client_company_id(),
        search_text=>filter_money_transactions.search_text,
        exclude_money_account_ids=>filter_money_transactions.exclude_money_account_ids,
        money_account_ids=>filter_money_transactions.money_account_ids,
        "type"=>filter_money_transactions."type"::text::money_transaction_type,
        from_date=>filter_money_transactions.from_date,
        until_date=>filter_money_transactions.until_date,
        min_amount=>filter_money_transactions.min_amount,
        max_amount=>filter_money_transactions.max_amount,
        min_matched_count=>filter_money_transactions.min_matched_count,
        max_matched_count=>filter_money_transactions.max_matched_count,
        exclude_money_category_ids=>filter_money_transactions.exclude_money_category_ids,
        money_category_ids=>filter_money_transactions.money_category_ids
    ) as mt
$$
language sql stable security definer; -- is ok because we lock the client_company argument

comment on function api.filter_money_transactions is 'Searches for money transactions with the given filter arguments';
