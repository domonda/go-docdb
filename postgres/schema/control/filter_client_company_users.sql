create function control.filter_client_company_users(
    client_company_id uuid,
    search_text       text = null
) returns setof control.client_company_user as
$$
    select ccu.* from control.client_company_user as ccu
        inner join public.user as u on (u.id = ccu.user_id)
    where (
        u.type in ('SUPER_ADMIN', 'STANDARD')
    ) and (
        u.enabled
    ) and (
        (filter_client_company_users.client_company_id is null) or (
            filter_client_company_users.client_company_id = ccu.client_company_id
        )
    ) and (
        (coalesce(trim(filter_client_company_users.search_text), '') = '') or (
            (
                u.email ilike '%' || filter_client_company_users.search_text || '%'
            ) or (
                u.first_name ilike '%' || filter_client_company_users.search_text || '%'
            ) or (
                u.last_name ilike '%' || filter_client_company_users.search_text || '%'
            )
        )
    )
$$
language sql stable;

comment on function control.filter_client_company_users is 'Filter `ClientCompanyUsers`.';
