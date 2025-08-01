create function rule.filter_reactions (
    client_company_id uuid,
    search_text       text = null
) returns setof rule.reaction as
$$
    select * from rule.reaction
    where (
        client_company_id = filter_reactions.client_company_id
    ) and (
        (coalesce(trim(filter_reactions.search_text), '') = '') or (
            (
                name ilike '%' || filter_reactions.search_text || '%'
            ) or (
                description ilike '%' || filter_reactions.search_text || '%'
            )
        )
    )
$$
language sql stable;
