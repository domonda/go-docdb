create function rule.filter_actions_reactions (
    client_company_id uuid,
    search_text       text = null,
    disabled          boolean = null
) returns setof rule.action_reaction as
$$
    select ar.* from rule.actions_reactions_by_client_company_id(filter_actions_reactions.client_company_id) as ar
        inner join rule.action as a on (a.id = ar.action_id)
        inner join rule.reaction as r on (r.id = ar.reaction_id)
    where (
        (coalesce(trim(filter_actions_reactions.search_text), '') = '') or (
            (
                ar.description ilike '%' || filter_actions_reactions.search_text || '%'
            ) or (
                a.name ilike '%' || filter_actions_reactions.search_text || '%'
            ) or (
                a.description ilike '%' || filter_actions_reactions.search_text || '%'
            ) or (
                r.name ilike '%' || filter_actions_reactions.search_text || '%'
            ) or (
                r.description ilike '%' || filter_actions_reactions.search_text || '%'
            )
        )
    ) and (
        filter_actions_reactions.disabled is null
            or filter_actions_reactions.disabled = ar.disabled
    )
$$
language sql stable;
