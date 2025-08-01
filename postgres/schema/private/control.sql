create function private.control_add_client_company_user(
    user_id                        uuid,
    client_company_id              uuid,
    role_name                      text,
    document_accounting_tab_access public.document_accounting_tab_access = null,
    approver_limit                 float8 = null
) returns control.client_company_user as
$$
  select control.add_client_company_user(
      control_add_client_company_user.user_id,
      control_add_client_company_user.client_company_id,
      control_add_client_company_user.role_name,
      control_add_client_company_user.document_accounting_tab_access,
      control_add_client_company_user.approver_limit
  );
$$
language sql volatile security definer;
