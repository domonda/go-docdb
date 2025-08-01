create function public.filter_users(
    client_company_id            uuid = null,
    has_access_to_client_company boolean = null,
    exclude_external             boolean = false,
    exclude_external_public_link boolean = false,
    user_group_id                uuid = null,
    approver_limit               float8 = null,
    search_text                  text = null
) returns setof public.user as $$
    select "user".* from public.user
    where "user"."type" in ('SUPER_ADMIN', 'STANDARD', 'EXTERNAL')
    and "user".enabled
    and (
        not exclude_external
        or not public.user_is_external("user")
    )
    and (
        not exclude_external_public_link
        or not public.user_is_external_public_link("user")
    )
    and (
        filter_users.user_group_id is null
        or exists (
            select from public.user_group_user
            where user_group_user.user_id = "user".id
            and user_group_user.user_group_id = filter_users.user_group_id
        )
    )
    and (
        filter_users.approver_limit is null
        or exists (
            select from control.client_company_user
            where client_company_user.user_id = "user".id
            and client_company_user.client_company_id = filter_users.client_company_id
            and (
                client_company_user.approver_limit is null
                or filter_users.approver_limit <= client_company_user.approver_limit
            )
        )
    )
    and (filter_users.client_company_id is null
        or (
            case when has_access_to_client_company then
                exists (
                    select from control.client_company_user
                    where client_company_user.user_id = "user".id
                    and client_company_user.client_company_id = filter_users.client_company_id
                )
                -- allows mentioning external users
                or (
                    "user"."type" = 'EXTERNAL'
                    and "user".client_company_id = filter_users.client_company_id
                )
                else "user".client_company_id = filter_users.client_company_id
            end
        )
    )
    and (
        coalesce(trim(filter_users.search_text), '') = ''
        or ("user".email ilike '%' || filter_users.search_text || '%')
        or (public.user_full_name_with_company("user") ilike '%' || filter_users.search_text || '%')
    )
$$ language sql stable;

create function public.filter_external_users(
    client_company_id uuid = null,
    search_text       text = null
) returns setof public.user as $$
    select * from public.filter_users(
        client_company_id=>filter_external_users.client_company_id,
        search_text=>filter_external_users.search_text
    )
    where "type" = 'EXTERNAL'
$$ language sql stable;
