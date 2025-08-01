create function public.filter_money_transactions_v2(
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
) returns setof public.money_transaction as
$$
begin
    return query execute builder.filter_money_transactions_query(
        client_company_id,
        money_transaction_ids,
        search_text,
        exclude_money_account_ids,
        money_account_ids,
        money_account_active,
        "type",
        from_date,
        until_date,
        min_amount,
        max_amount,
        min_matched_count,
        max_matched_count,
        exclude_money_category_ids,
        money_category_ids,
        exclude_cash_transactions
    );
end
$$
language plpgsql stable;

----

create type public.filter_money_transactions_v2_statistics_result as (
    incoming_amount_sum             float8,
    outgoing_amount_sum             float8,
    balance_sum                     float8,
    all_money_accounts_have_balance boolean
);

comment on column public.filter_money_transactions_v2_statistics_result.incoming_amount_sum is '@notNull';
comment on column public.filter_money_transactions_v2_statistics_result.outgoing_amount_sum is '@notNull';
comment on column public.filter_money_transactions_v2_statistics_result.all_money_accounts_have_balance is '@notNull';

create function public.filter_money_transactions_v2_statistics(
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
) returns public.filter_money_transactions_v2_statistics_result as
$$
    select
        sum(case money_transaction."type" when 'INCOMING' then money_transaction.amount else 0 end) as incoming_amount_sum,
        sum(case money_transaction."type" when 'OUTGOING' then money_transaction.amount else 0 end) as outgoing_amount_sum,
        private.dist_sum(distinct money_account.id, round(public.money_account_balance_until(money_account, until_date)::numeric, 2)) filter (where money_account.active) as balance_sum,
        coalesce(every(public.money_account_balance_until(money_account, until_date) is not null) filter (where money_account.active), false) as all_money_accounts_have_balance
    from public.filter_money_transactions_v2(
        client_company_id,
        money_transaction_ids,
        search_text,
        exclude_money_account_ids,
        money_account_ids,
        money_account_active,
        "type",
        from_date,
        until_date,
        min_amount,
        max_amount,
        min_matched_count,
        max_matched_count,
        exclude_money_category_ids,
        money_category_ids,
        exclude_cash_transactions
    ) as money_transaction
      inner join public.money_account on money_account.id = money_transaction.account_id
$$
language sql stable;
