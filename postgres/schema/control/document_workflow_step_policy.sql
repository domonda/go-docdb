---- has to either ----

-- be a super admin
create policy document_workflow_step_super_admin_policy on public.document_workflow_step
  as permissive
  for all
  to domonda_user
  using (
    private.current_user_super()
  );

-- have a document workflow step control entry
create policy document_workflow_step_control_exists on public.document_workflow_step
  as permissive
  for all
  to domonda_user
  using (
    exists (
      select 1 from control.document_workflow_step_access as dwsa
        -- we inner join because we want to check if the user has access to the workflow itself and because we need it to find the client company user
        inner join public.document_workflow as dw on (dw.id = document_workflow_step.workflow_id)
        inner join (
          control.document_workflow_access as dwa
          inner join control.client_company_user as ccu on (
            (
              ccu.user_id = (select id from private.current_user())
            ) and (
              ccu.id = dwa.client_company_user_id
            )
          )
        ) on (dwa.id = dwsa.document_workflow_access_id)
      where (
        ccu.client_company_id = dw.client_company_id
      ) and (
        (dwa.document_workflow_id is null) or (
          dwa.document_workflow_id = document_workflow_step.workflow_id
        )
      ) and (
        (dwsa.document_workflow_step_id is null) or (
          dwsa.document_workflow_step_id = document_workflow_step.id
        )
      )
    )
  );

----

alter table public.document_workflow_step enable row level security;
