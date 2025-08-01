create function public.client_company_open_approval_requests_for_current_user(
  client_company public.client_company
) returns int as $$
    select count(1)::int -- shouldnt grow beyond int (not bigint)
    from public.filter_documents_v2(
      client_company_id=>client_company.company_id,
      superseded=>false,
      archived=>false,
      is_approved=>false,
      requested_approver_ids=>array[private.current_user_id()]
    )
$$ language sql stable strict;
comment on function public.client_company_open_approval_requests_for_current_user is '@notNull';
