---- has to ----

-- have access to the client company
create policy document_client_company_policy on public.document
  as restrictive
  for all
  to domonda_user
  using (
    (select private.current_user_super())
    -- checkout user can always work on the document (TODO-db-201116 access control should prevent unauthorized checkouts)
    or document.checkout_user_id = (select private.current_user_id())
    -- user had done something on the document
    or exists (
      select from public.document_log
      where document_id = document.id
      and user_id = (select private.current_user_id()))
    -- has access to the client company
    or exists (select from control.client_company_user
      where user_id = (select private.current_user_id())
      and client_company_id = document.client_company_id)
  );

-- have access to the document category
create policy document_category_policy on public.document
  as restrictive
  for all
  to domonda_user
  using (
    (select private.current_user_super())
    -- checkout user can always work on the document (TODO-db-201116 access control should prevent unauthorized checkouts)
    or document.checkout_user_id = (select private.current_user_id())
    -- has access to the document category
    or exists (select from control.document_category_access as dca
        inner join control.client_company_user as ccu
        on ccu.user_id = (select private.current_user_id())
        and ccu.id = dca.client_company_user_id
        and ccu.client_company_id = document.client_company_id
      where dca.document_category_id is null
      or dca.document_category_id = document.category_id)
  );

-- have access to the workflow step (and the workflow)
create policy document_workflow_step_policy on public.document
  as restrictive
  for all
  to domonda_user
  using (
    (select private.current_user_super())
    -- checkout user can always work on the document (TODO-db-201116 access control should prevent unauthorized checkouts)
    or document.checkout_user_id = (select private.current_user_id())
    -- user had done something on the document
    or exists (
      select from public.document_log
      where document_id = document.id
      and user_id = (select private.current_user_id()))
    -- document has no workflow
    or document.workflow_step_id is null
    -- document has workflow and user has access
    or exists (select from control.document_workflow_step_access as dwsa
        inner join (control.document_workflow_access as dwa
          inner join control.client_company_user as ccu
          on ccu.user_id = (select private.current_user_id())
          and ccu.id = dwa.client_company_user_id)
        on (dwa.id = dwsa.document_workflow_access_id)
      where ccu.client_company_id = document.client_company_id
      and (dwa.document_workflow_id is null
        or dwa.document_workflow_id = (select workflow_id from public.document_workflow_step where id = document.workflow_step_id))
      and ((dwsa.document_workflow_step_id is null)
        or (dwsa.document_workflow_step_id = document.workflow_step_id)))
    -- had previously changed the workflow step
    or exists (select from public.document_workflow_step_log as dwsl
      where dwsl.user_id = (select private.current_user_id())
      and dwsl.document_id = document.id)
    -- has an approval request
    or exists (
      select from public.document_approval_request
      where document_approval_request.approver_id is not null
      and document_approval_request.approver_id = (select private.current_user_id())
      and document_approval_request.document_id = document.id
      -- TODO-db-210623 should blank approval requests be considered too?
    )
    -- had previously approved the document
    or exists (
      select from public.document_approval
        inner join public.document_approval_request on document_approval_request.id = document_approval.request_id
      where document_approval.approver_id = (select private.current_user_id())
      and document_approval_request.document_id = document.id)
  );

---- in addition has to either ----

-- be a super admin
create policy document_super_user_user_policy on public.document
  as permissive
  for all
  to domonda_user
  using ((select private.current_user_super()));

-- be the checkout user
create policy document_checkout_user_policy on public.document
  as permissive
  for all
  to domonda_user
  using (document.checkout_user_id = (select private.current_user_id()));

-- be the import user
create policy document_import_user_policy on public.document
  as permissive
  for all
  to domonda_user
  using (document.imported_by = (select private.current_user_id()));

-- have done something on the document (apply/put in review group, delete/restore, etc.)
create policy document_user_with_document_log_policy on public.document
  as permissive
  for all
  to domonda_user
  using (exists (
    select from public.document_log
    where document_id = document.id
    and user_id = (select private.current_user_id())
  ));

-- pass the control document filter
create policy document_filter_policy on public.document
  as permissive
  for all
  to domonda_user
  using (
    exists (select from control.document_filter as df
        inner join control.client_company_user as ccu
        on ccu.user_id = (select private.current_user_id())
        and ccu.id = df.client_company_user_id
        and ccu.client_company_id = document.client_company_id
      where (df.has_workflow_step is null
          or df.has_workflow_step = (document.workflow_step_id is not null))
        and (df.has_approval_request is null
          or exists (select from public.document_approval_request as dar
            where dar.document_id = document.id
            and (
              ((dar.blank_approver_type = 'ANYONE')
                and (exists (select from control.client_company_user
                  where client_company_id = document.client_company_id
                  and user_id = (select private.current_user_id())
                  and role_name <> 'VERIFIER')))
              or ((dar.blank_approver_type = 'ACCOUNTANT')
                and (exists (select from control.client_company_user
                  where client_company_id = document.client_company_id
                  and user_id = (select private.current_user_id())
                  and role_name = 'ACCOUNTANT')))
              or ((dar.blank_approver_type = 'VERIFIER')
                and (exists (select from control.client_company_user
                  where client_company_id = document.client_company_id
                  and user_id = (select private.current_user_id())
                  and role_name = 'VERIFIER')))
              or dar.user_group_id in (
                select user_group_user.user_group_id from public.user_group_user
                where user_group_user.user_id = (select private.current_user_id())
              )
              or approver_id = (select private.current_user_id())))))
  );

----

alter table public.document enable row level security;
