create function automation.validate_action() returns trigger as $$
declare
  trigger_table     text := (tg_table_schema || '.' || tg_table_name);
  trigger_action    record;
  trigger_action_id uuid;
begin
  if tg_op = 'DELETE' then
    trigger_action = old;
  else
    trigger_action = new;
  end if;

  case trigger_table
    when 'automation.action' then
      trigger_action_id := trigger_action.id;
    when 'automation.action_set_document_workflow_step' then
      trigger_action_id := trigger_action.action_id;

      if tg_op <> 'DELETE'
      and trigger_action_id in (
        select action_id from automation.action_create_direct_document_approval_request
      ) then
        raise exception 'Only one action per action is allowed';
      end if;
    when 'automation.action_create_direct_document_approval_request' then
      trigger_action_id := trigger_action.action_id;

      if tg_op <> 'DELETE'
      and trigger_action_id in (
        select action_id from automation.action_set_document_workflow_step
      ) then
        raise exception 'Only one action per action is allowed';
      end if;
  end case;

  -- when applying changes, the action mustnt be in use
  if not automation.current_user_is_special()
  and exists (select from automation.action_on_document_log
    where action_on_document_log.action_id = trigger_action_id
    -- skip errored action runs, they can be seen as "not run"
    and error_msg is null)
  then
    raise exception 'Cannot change action because it is in use.';
  end if;

  return trigger_action;
end
$$ language plpgsql stable;

----

create trigger automation_action_on_delete_trigger
  before delete
  on automation.action
  for each row
  execute procedure automation.validate_action();

create trigger automation_action_set_document_workflow_step_change_trigger
  before insert or update or delete
  on automation.action_set_document_workflow_step
  for each row
  execute procedure automation.validate_action();

create trigger automation_action_create_dir_doc_appr_req_change_trigger
  before insert or update or delete
  on automation.action_create_direct_document_approval_request
  for each row
  execute procedure automation.validate_action();
