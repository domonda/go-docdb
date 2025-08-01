create table super.client_company_users_dump (
  id   text primary key,
  dump json
);

create index super_client_company_users_dump_id_trgm_idx on super.client_company_users_dump using gin (id gin_trgm_ops);

create function super.set_client_company_users_dump(
  client_company_users_dump_id text,
  set_for_user_id uuid,
  extend boolean
) returns setof control.client_company_user as $$
declare
  dump json;
  dump_i json;
  dump_j json;

  client_company_user_id uuid;
  document_workflow_access_id uuid;
begin
  if not exists (
    select from super.client_company_users_dump
    where id = client_company_users_dump_id
  )
  then
    raise exception 'client company users dump with id % does not exist', client_company_users_dump_id;
  end if;

  if not extend
  then
    -- remove existing access rights
    delete from control.client_company_user
    where user_id = set_for_user_id;

    -- remove from existing user groups
    delete from public.user_group_user
    where user_id = set_for_user_id;
  end if;

  for dump in (
    select json_array_elements from
      super.client_company_users_dump,
      json_array_elements(client_company_users_dump.dump)
    where id = client_company_users_dump_id
  )
  loop
    if not extend
    then
      client_company_user_id := uuid_generate_v4();

      insert into control.client_company_user (id, user_id, client_company_id, role_name, document_accounting_tab_access, approver_limit)
      values (client_company_user_id, set_for_user_id, (dump->>'clientCompanyId')::uuid, dump->>'roleName', (dump->>'documentAccountingTabAccess')::public.document_accounting_tab_access, (dump->>'approverLimit')::float8);

      insert into control.document_filter (client_company_user_id, has_invoice, has_workflow_step, has_approval_request)
      values (client_company_user_id, (dump->'documentFilter'->>'hasInvoice')::boolean, (dump->'documentFilter'->>'hasWorkflowStep')::boolean, (dump->'documentFilter'->>'hasApprovalRequest')::boolean);

      for dump_i in (
        select * from json_array_elements(dump->'documentCategoryAccesses')
      )
      loop
        insert into control.document_category_access (id, client_company_user_id, document_category_id)
        values (uuid_generate_v4(), client_company_user_id, (dump_i->>'documentCategoryId')::uuid);
      end loop;

      for dump_i in (
        select * from json_array_elements(dump->'documentWorkflowAccesses')
      )
      loop
        document_workflow_access_id := uuid_generate_v4();

        insert into control.document_workflow_access (id, client_company_user_id, document_workflow_id)
        values (document_workflow_access_id, client_company_user_id, (dump_i->>'documentWorkflowId')::uuid);

        for dump_j in (
          select * from json_array_elements(dump_i->'documentWorkflowStepAccesses')
        )
        loop
          insert into control.document_workflow_step_access (id, document_workflow_access_id, document_workflow_step_id)
          values (uuid_generate_v4(), document_workflow_access_id, (dump_j->>'documentWorkflowStepId')::uuid);
        end loop;
      end loop;
    end if;

    for dump_i in (
      select * from json_array_elements(dump->'userGroups')
    )
    loop
      if dump_i->>'id' is not null
      then
        insert into public.user_group_user (user_group_id, user_id)
        values ((dump_i->>'id')::uuid, set_for_user_id);
      else
        insert into public.user_group_user (user_group_id, user_id)
        select id, set_for_user_id from public.user_group
        where client_company_id = (dump->>'clientCompanyId')::uuid
        and name = (dump_i->>'name');
      end if;
    end loop;

    return query select * from control.client_company_user where id = client_company_user_id;
  end loop;
end
$$ language plpgsql volatile;
