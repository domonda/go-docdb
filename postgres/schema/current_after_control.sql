create function public.client_company_client_company_user_for_current_user(
  client_company public.client_company
) returns control.client_company_user as
$$
  select *
  from control.client_company_user
  where user_id = private.current_user_id()
  and client_company_id = client_company.company_id
$$ language sql stable;
comment on function public.client_company_client_company_user_for_current_user is 'Client user for the this client company and the current user. Should always return a client user because the user already sees the client which means that he already has access, but not necessarily true for super-users.';
