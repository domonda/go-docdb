-- domonda_user policy is required because domonda_wg_user has specific RLS policies
-- see: document_comment_policies.sql

create policy document_comment_client_company_policy on public.document_comment
  as permissive
  for all
  to domonda_user
  using (
    -- TODO: implement properly
    true
  );

alter table public.document_comment enable row level security;
