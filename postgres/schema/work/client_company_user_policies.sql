create policy select_control_client_company_user_everything on control.client_company_user
  as permissive
  for select
  to domonda_wg_user
  using (
    -- TODO: implement a proper check
    true
  );

alter table control.client_company_user enable row level security;
