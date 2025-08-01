create policy user_select_policy on public.user
    for select
    to domonda_user
    using (true);

create policy user_update_policy on public.user
    for update
    to domonda_user
    using (true) -- always true, update policy should be implemented in with check
    with check (
        "user".id = (select private.current_user_id())
        or private.current_user_super()
        or exists (
            select from control.client_company_user as client_company_user
                inner join control.client_company_user_role as client_company_user_role on client_company_user_role.name = client_company_user.role_name
            where client_company_user.user_id = (select private.current_user_id())
            and client_company_user.client_company_id = "user".client_company_id
            and client_company_user_role.update_users)
    );

----

alter table public.user enable row level security;
