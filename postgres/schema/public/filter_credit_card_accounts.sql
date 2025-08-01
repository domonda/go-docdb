create function public.filter_credit_card_accounts(
    client_company_id uuid,
    search_text       text = null,
    active            boolean = null
) returns setof public.credit_card_account as
$$
    select * from public.credit_card_account
    where (
        client_company_id = filter_credit_card_accounts.client_company_id
    ) and (
        (coalesce(trim(filter_credit_card_accounts.search_text), '') = '') or (
            (
                "number" ilike '%' || filter_credit_card_accounts.search_text || '%'
            ) or (
                "type"::text ilike '%' || filter_credit_card_accounts.search_text || '%'
            ) or (
                name ilike '%' || filter_credit_card_accounts.search_text || '%'
            )
        )
    ) and (
        filter_credit_card_accounts.active is null
        or (active = filter_credit_card_accounts.active)
    )
    order by
        active desc
$$
language sql stable;
