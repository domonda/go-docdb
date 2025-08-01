create function rule.filter_actions (
    client_company_id uuid,
    search_text       text = null
) returns setof rule.action as
$$
    select * from rule.action
    where (
        client_company_id = filter_actions.client_company_id
    ) and (
        (coalesce(trim(filter_actions.search_text), '') = '') or (
            (
                name ilike '%' || filter_actions.search_text || '%'
            ) or (
                description ilike '%' || filter_actions.search_text || '%'
            )
        )
    )
$$
language sql stable;
