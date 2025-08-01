---- has to either ----

-- be a super admin
create policy client_company_super_admin_policy on public.client_company
  as permissive
  for select
  to domonda_user
  using (
    private.current_user_super()
  );

-- belong to the company
create policy client_company_user_belongs_policy on public.client_company
  as permissive
  for select
  to domonda_user
  using (
    client_company.company_id = (private.current_user()).client_company_id
  );

-- have a client company control entry
create policy client_company_control_exists_policy on public.client_company
  as permissive
  for select
  to domonda_user
  using (
    exists (
      select 1 from control.client_company_user
      where (
        user_id = (select id from private.current_user())
      ) and (
        client_company_id = client_company.company_id
      )
    )
  );

----

create policy client_company_insert_policy on public.client_company
  for insert
  to domonda_user
  with check (true); -- TODO-db-200224: implement

----

create policy client_company_update_policy on public.client_company
  for update
  to domonda_user
  using (true) -- always true, update policy should be implemented in with check, todo: test
  with check (
    private.current_user_super() or (
      exists (
        select 1 from control.client_company_user as ccu
          inner join control.client_company_user_role as ccur on (ccur.name = ccu.role_name)
        where (
          ccu.user_id = (select id from private.current_user())
        ) and (
          ccu.client_company_id = client_company.company_id
        ) and (
          ccur.update_company = true
        )
      )
    )
  );

----

create policy client_company_delete_policy on public.client_company
  for delete
  to domonda_user
  using (false); -- deleting client companies can be done through the backend only

----

alter table public.client_company enable row level security;
