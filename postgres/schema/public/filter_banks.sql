create function public.filter_banks(
    search_text text = null
) returns setof public.bank as
$$
    select * from public.bank
    where (
        (coalesce(trim(filter_banks.search_text), '') = '') or (
            (
                legal_name ilike '%' || filter_banks.search_text || '%'
            ) or (
                brand_name ilike '%' || filter_banks.search_text || '%'
            ) or (
                bic ilike '%' || filter_banks.search_text || '%'
            )
        )
    )
$$
language sql stable;
