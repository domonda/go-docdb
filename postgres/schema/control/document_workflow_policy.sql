---- has to either ----

-- be a super admin
create policy document_workflow_super_admin_policy on public.document_workflow
  as permissive
  for all
  to domonda_user
  using (
    private.current_user_super()
  );

-- have a document workflow control entry
create policy document_workflow_control_exists_policy on public.document_workflow
  as permissive
  for all
  to domonda_user
  using (
    exists (
      select 1 from control.document_workflow_access as dwa
        inner join control.client_company_user as ccu on (
          (
            ccu.user_id = (select id from private.current_user())
          ) and (
            ccu.id = dwa.client_company_user_id
          )
        )
      where (
        ccu.client_company_id = document_workflow.client_company_id
      ) and (
        (
          dwa.document_workflow_id is null
        ) or (
          dwa.document_workflow_id = document_workflow.id
        )
      )
    )
  );

----

alter table public.document_workflow enable row level security;
