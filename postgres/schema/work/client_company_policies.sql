create policy client_company_user_is_super on public.client_company
  as permissive
  for select
  to domonda_wg_user
  using (private.current_user_super());

create policy client_company_user_belongs on public.client_company
  as permissive
  for select
  to domonda_wg_user
  using (
    client_company.company_id = (private.current_user()).client_company_id
  );

create policy client_company_user_has_access_to_some_document on public.client_company
  as permissive
  for select
  to domonda_wg_user
  using (
    true -- TODO
  );

----

alter table public.client_company enable row level security;
