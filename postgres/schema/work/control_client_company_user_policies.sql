---- select

create policy control_client_company_user_domonda_wg_user_select_all on control.client_company_user
  for select
  to domonda_wg_user
  using (true);

----

alter table control.client_company_user enable row level security;
