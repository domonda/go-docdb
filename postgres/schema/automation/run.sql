create function automation.run_workflow(
  workflow automation.workflow,
  payload  jsonb, -- see automation.action_on_document_log.payload
  document public.document
) returns boolean as $$
declare
  root_action_id uuid;
begin
  -- better safe than sorry
  if workflow.client_company_id <> document.client_company_id
  then
    raise exception 'Workflow % does not belong to the document''s % client company.', workflow.id, document.id;
  end if;

  if automation.check_workflow_trigger_filters(
    workflow,
    payload,
    document
  ) is not distinct from false
  then
    -- null = no filters
    -- true = filters passed
    -- false = filters exist and didnt pass
    return false;
  end if;

  select id into root_action_id
  from automation.action
  where action.workflow_id = workflow.id
  and action.after_action_id is null; -- chained actions will be performed by the worker

  if exists (select from automation.action_on_document_log
    where action_id = root_action_id
    and document_id = document.id
    and automation.action_on_document_log_pending(action_on_document_log))
  then
    -- a job is already pending, no need to create a new one
    return false;
  end if;

  -- creating action logs will in turn create appropriate worker jobs (see automation.create_job_for_action_on_document_log)
  insert into automation.action_on_document_log (action_id, payload, document_id, created_by)
  values (
    root_action_id,
    payload,
    document.id,
    coalesce(private.current_user_id(), '08a34dc4-6e9a-4d61-b395-d123005e65d3') -- coalesce to SYSTEM Unknown because the backend doesnt set the current.user_id
  );

  -- workflow ran
  return true;
end
$$ language plpgsql volatile;
comment on function automation.run_workflow is '@omit';

create function automation.run() returns trigger as $$
declare
  tg_table text := (tg_table_schema || '.' || tg_table_name);

  payload jsonb;

  the_document public.document;

  detected_workflow_triggers automation.workflow_trigger_type[] = '{}';

  workflow_first_group_id uuid;
  matched_workflow        automation.workflow;
  matched_workflow_ran    boolean;
begin
  if private.current_setting_flag('current.disable_automation')
  then
    -- for example: when cloning a company
    return null;
  end if;

  -- the thing that triggered the workflow (see automation.action_on_document_log.payload)
  payload := jsonb_build_object(
    'tg_op', tg_op,
    'tg_name', tg_name,
    'tg_table', tg_table,
    'tg_row', to_jsonb(new)
  );

  -- extract related document
  case tg_table
  when 'rule.document_ready' then
    select document.* into the_document
    from public.document
    where document.id = new.document_id;
  when 'public.document' then
    the_document = new;
  when 'public.document_approval' then
    select document.* into the_document
    from public.document
      inner join public.document_approval_request on document_approval_request.document_id = document.id
    where document_approval_request.id = new.request_id;
  when 'public.invoice' then
    select document.* into the_document
    from public.document
    where document.id = new.document_id;
  when 'public.other_document' then
    select document.* into the_document
    from public.document
    where document.id = new.document_id;
  else
    raise exception 'Cannot run automation on table %', tg_table;
  end case;

  -- make sure there's a document
  if the_document is null
  then
    raise exception 'Cannot find the document for automation';
  end if;

  -- bail out if the document is not ready
  if not rule.is_document_ready(the_document.id) then
    return null;
  end if;

  -- detect workflow triggers
  case tg_name
  when 'automation_document_ready_trigger' then
    detected_workflow_triggers := '{DOCUMENT_READY,DOCUMENT_CHANGED}';
  when 'automation_document_workflow_changed_trigger' then
    detected_workflow_triggers := '{DOCUMENT_WORKFLOW_CHANGED}';
  when 'automation_document_approval_approved_trigger' then
    detected_workflow_triggers := '{DOCUMENT_APPROVAL_APPROVED}';
  when 'automation_invoice_changed_trigger' then
    detected_workflow_triggers := '{DOCUMENT_CHANGED}';
  when 'automation_other_document_changed_trigger' then
    detected_workflow_triggers := '{DOCUMENT_CHANGED}';
  else
    raise exception 'Cannot run automation with trigger %', tg_name;
  end case;

  -- first check grouped workflows
  <<workflow_first_groups_loop>>
  for workflow_first_group_id in (
    select id from automation.workflow_first_group
    where workflow_first_group.client_company_id = the_document.client_company_id
  )
  loop
    for matched_workflow in (
      select workflow.*
      from automation.workflow_first_group_workflow
        inner join automation.workflow on workflow.id = workflow_first_group_workflow.workflow_id
      where workflow_first_group_workflow.group_id = workflow_first_group_id
      and workflow.enabled
      and workflow.trigger_type = any(detected_workflow_triggers)
      order by index asc
    )
    loop
      matched_workflow_ran := automation.run_workflow(matched_workflow, payload, the_document);
      continue workflow_first_groups_loop when matched_workflow_ran;
    end loop;
  end loop;

  -- and then lone workflows
  for matched_workflow in (
    select *
    from automation.workflow
    where workflow.client_company_id = the_document.client_company_id
    and workflow.enabled
    and workflow.trigger_type = any(detected_workflow_triggers)
    and not exists(select from automation.workflow_first_group_workflow
      where workflow_id = workflow.id)
  )
  loop
    perform automation.run_workflow(matched_workflow, payload, the_document);
  end loop;

  return null;
end
$$ language plpgsql volatile
security definer; -- necessary for inserting action_logs and contextless view on the db

----

-- workflow_trigger_type = '{DOCUMENT_READY,DOCUMENT_CHANGED}'
create trigger automation_document_ready_trigger
  after insert on rule.document_ready
  for each row
  when (new.is_ready)
  execute procedure automation.run();

-- workflow_trigger_type = '{DOCUMENT_WORKFLOW_CHANGED}'
create trigger automation_document_workflow_changed_trigger
  after update on public.document
  for each row
  when (old.workflow_step_id is distinct from new.workflow_step_id)
  execute procedure automation.run();

-- workflow_trigger_type = '{DOCUMENT_APPROVAL_APPROVED}'
create trigger automation_document_approval_approved_trigger
  after insert on public.document_approval
  for each row
  when (new.next_request_id is null
    and not new.canceled)
  execute procedure automation.run();

-- workflow_trigger_type = '{DOCUMENT_CHANGED}'
create trigger automation_invoice_changed_trigger
  after insert or update on public.invoice
  for each row
  execute procedure automation.run();

-- workflow_trigger_type = '{DOCUMENT_CHANGED}'
create trigger automation_other_document_changed_trigger
  after insert or update on public.other_document
  for each row
  execute procedure automation.run();
