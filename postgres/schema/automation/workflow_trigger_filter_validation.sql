create function automation.validate_workflow_trigger_filter() returns trigger as $$
declare
  tg_table text := (tg_table_schema || '.' || tg_table_name);
  trigger_filter record;
  trigger_workflow_id uuid;
begin
  if tg_op = 'DELETE' then
    trigger_filter = old;
  else
    trigger_filter = new;
  end if;

  if tg_table = 'automation.workflow_trigger_filter_group'
  then
    trigger_workflow_id = trigger_filter.workflow_id;
  else
    select workflow_id into trigger_workflow_id
    from automation.workflow_trigger_filter_group
    where id = trigger_filter.group_id; -- all other filters have a group_id
  end if;

  -- when applying changes, the trigger filter mustnt be in use
  if not automation.current_user_is_special()
  and exists (select from automation.action_on_document_log
      inner join automation.action on action.id = action_on_document_log.action_id
    where action.workflow_id = trigger_workflow_id
    -- TODO: skip errored action runs, they can be seen as "not run"
    -- and error_msg is null
  )
  then
    raise exception 'Cannot change trigger filter because the workflow is in use.';
  end if;

  return trigger_filter;
end
$$ language plpgsql stable;

----

create trigger workflow_trigger_filter_group_change
  before insert or delete -- update not possible
  on automation.workflow_trigger_filter_group_document_of_category_type
  for each row
  execute procedure automation.validate_workflow_trigger_filter();

create trigger workflow_trigger_filter_group_document_of_category_type_change
  before insert or update or delete
  on automation.workflow_trigger_filter_group_document_of_category_type
  for each row
  execute procedure automation.validate_workflow_trigger_filter();

create trigger workflow_trigger_filter_group_document_in_workflow_step_change
  before insert or update or delete
  on automation.workflow_trigger_filter_group_document_in_workflow_step
  for each row
  execute procedure automation.validate_workflow_trigger_filter();

create trigger workflow_trigger_filter_group_direct_document_approval_approved_change
  before insert or update or delete
  on automation.workflow_trigger_filter_group_direct_document_approval_approved
  for each row
  execute procedure automation.validate_workflow_trigger_filter();

create trigger workflow_trigger_filter_group_document_with_partner_change
  before insert or update or delete
  on automation.workflow_trigger_filter_group_document_with_partner
  for each row
  execute procedure automation.validate_workflow_trigger_filter();

create trigger workflow_trigger_filter_group_invoice_with_total_change
  before insert or update or delete
  on automation.workflow_trigger_filter_group_invoice_with_total
  for each row
  execute procedure automation.validate_workflow_trigger_filter();
