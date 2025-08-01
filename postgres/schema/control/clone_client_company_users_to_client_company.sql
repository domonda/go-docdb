-- TODO-db-210614 category mapping
-- NOTE: workflow step full names must match exactly between the src and dest
create function control.clone_client_company_users_to_client_company(
  src_client_company_id  uuid,
  dest_client_company_id uuid
) returns setof control.client_company_user as $$
declare
  src  control.client_company_user;
  dest control.client_company_user;

  src_workflow     control.document_workflow_access;
  dest_workflow_id uuid;
begin
  for src in (
    select * from control.client_company_user
    where client_company_id = src_client_company_id
    and not exists (select from control.client_company_user as dest_user
      where dest_user.client_company_id = dest_client_company_id
      and dest_user.user_id = client_company_user.user_id)
  ) loop

    insert into control.client_company_user (id, user_id, client_company_id, role_name, document_accounting_tab_access, approver_limit)
      values (uuid_generate_v4(), src.user_id, dest_client_company_id, src.role_name, src.document_accounting_tab_access, src.approver_limit)
    returning * into dest;

    -- control.document_filter
    insert into control.document_filter (client_company_user_id, has_workflow_step, has_invoice, has_approval_request)
      select dest.id, document_filter.has_workflow_step, document_filter.has_invoice, document_filter.has_approval_request from control.document_filter
      where document_filter.client_company_user_id = src.id;

    -- control.document_category_access
    if exists(select from control.document_category_access
      where client_company_user_id = src.id
      and document_category_id is not null)
    then
      raise exception 'Cloning users with document category access not supported';
    end if;
    insert into control.document_category_access (id, client_company_user_id, document_category_id)
      select uuid_generate_v4(), dest.id, document_category_access.document_category_id from control.document_category_access
      where document_category_access.client_company_user_id = src.id;

    -- control.document_workflow_access
    for src_workflow in (
      select * from control.document_workflow_access
      where client_company_user_id = src.id
    ) loop

      insert into control.document_workflow_access (id, client_company_user_id, document_workflow_id)
        values (uuid_generate_v4(), dest.id, (public.find_document_workflow_in_client_company(src_workflow.document_workflow_id, dest_client_company_id)).id)
      returning document_workflow_access.id into dest_workflow_id;

      -- control.document_workflow_step_access
      insert into control.document_workflow_step_access (id, document_workflow_access_id, document_workflow_step_id)
        select uuid_generate_v4(), dest_workflow_id, (public.find_document_workflow_step_in_client_company(document_workflow_step_id, dest_client_company_id)).id from control.document_workflow_step_access as src_step
        where src_step.document_workflow_access_id = src_workflow.id;

    end loop;

    return next dest;

  end loop;
end
$$ language plpgsql volatile strict;
