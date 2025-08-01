---- has to either ----

-- be as super admin
create policy document_category_super_admin_policy on public.document_category
  as permissive
  for select
  to domonda_user
  using (
    private.current_user_super()
  );

-- have a document category control entry
create policy document_category_control_exists_policy on public.document_category
  as permissive
  for select
  to domonda_user
  using (
    exists (
      select 1 from control.document_category_access as dca
        inner join control.client_company_user as ccu on (
          ccu.user_id = (select id from private.current_user())
        ) and (
          ccu.id = dca.client_company_user_id
        ) and (
          ccu.client_company_id = document_category.client_company_id
        )
      where (
        dca.document_category_id is null
      ) or (
        dca.document_category_id = document_category.id
      )
    )
  );

----

create policy document_category_insert_policy on public.document_category
  for insert
  to domonda_user
  with check (
    private.current_user_super() or (
      exists (
        select 1 from control.client_company_user as ccu
          inner join control.client_company_user_role as ccur on (ccur.name = ccu.role_name)
        where (
          ccu.user_id = (select id from private.current_user())
        ) and (
          ccu.client_company_id = document_category.client_company_id
        ) and (
          ccur.add_document_categories = true
        )
      )
    )
  );

----

create policy document_category_update_policy on public.document_category
  for update
  to domonda_user
  using (true) -- always true, update policy should be implemented in with check
  with check (
    private.current_user_super() or (
      exists (
        select 1 from control.client_company_user as ccu
          inner join control.client_company_user_role as ccur on (ccur.name = ccu.role_name)
        where (
          ccu.user_id = (select id from private.current_user())
        ) and (
          ccu.client_company_id = document_category.client_company_id
        ) and (
          ccur.update_document_categories = true
        )
      )
    )
  );

----

create policy document_category_delete_policy on public.document_category
  for delete
  to domonda_user
  using (
    private.current_user_super() or (
      exists (
        select 1 from control.client_company_user as ccu
          inner join control.client_company_user_role as ccur on (ccur.name = ccu.role_name)
        where (
          ccu.user_id = (select id from private.current_user())
        ) and (
          ccu.client_company_id = document_category.client_company_id
        ) and (
          ccur.delete_document_categories = true
        )
      )
    )
  );

----

alter table public.document_category enable row level security;
