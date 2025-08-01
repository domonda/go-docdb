-- TODO: automation.action_on_webhook_log
-- TODO: automation.action_cron_log

create table automation.action_on_document_log (
  id uuid primary key default uuid_generate_v4(),

  action_id uuid not null references automation.action(id) on delete restrict, -- cannot be deleted while in use (to delete, remove logs first)

  payload jsonb not null, -- the thing that triggered the workflow
  constraint payload_must_have_tg_op check(payload->'tg_op' is not null),
  constraint payload_must_have_tg_name check(payload->'tg_name' is not null),
  constraint payload_must_have_tg_table check(payload->'tg_table' is not null),
  constraint payload_must_have_tg_row check(payload->'tg_row' is not null),
  constraint payload_tg_row_must_be_object check(jsonb_typeof(payload->'tg_row') = 'object'),

  document_id uuid not null references public.document(id) on delete cascade,

  started_at timestamptz, -- when the job worker picked up the action
  ended_at   timestamptz, -- when the job worker ended working on the action

  error_msg      text, -- for developers
  nice_error_msg text, -- for users
  constraint nice_error_msg_must_exist_with_error_msg check(
    case when nice_error_msg is not null
      then error_msg is not null
      else true
    end
  ),

  -- who triggered the action?
  created_by uuid not null
    default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
    references public.user(id) on delete set default,

  updated_at updated_time not null,
  created_at created_time not null
);

grant select on automation.action_on_document_log to domonda_user;
grant select on automation.action_on_document_log to domonda_wg_user;

create index automation_action_on_document_log_action_id_idx on automation.action_on_document_log (action_id);
create index automation_action_on_document_log_payload_idx on automation.action_on_document_log using gin (payload);
create index automation_action_on_document_log_document_id_idx on automation.action_on_document_log (document_id);
create index automation_action_on_document_log_started_at_idx on automation.action_on_document_log (started_at);
create index automation_action_on_document_log_ended_at_idx on automation.action_on_document_log (ended_at);
create index automation_action_on_document_log_error_msg_idx on automation.action_on_document_log (error_msg);
create index automation_action_on_document_log_created_by_idx on automation.action_on_document_log (created_by);

create function automation.action_on_document_log_errored(
  action_on_document_log automation.action_on_document_log
) returns boolean as $$
  select action_on_document_log.error_msg is not null
$$ language sql immutable strict;
comment on function automation.action_on_document_log_errored is '@notNull';
create index automation_action_on_document_log__errored_idx on automation.action_on_document_log (automation.action_on_document_log_errored(action_on_document_log));

create function automation.action_on_document_log_success(
  action_on_document_log automation.action_on_document_log
) returns boolean as $$
  select not automation.action_on_document_log_errored(action_on_document_log)
  and action_on_document_log.ended_at is not null
$$ language sql immutable strict;
comment on function automation.action_on_document_log_success is '@notNull';
create index automation_action_on_document_log__success_idx on automation.action_on_document_log (automation.action_on_document_log_success(action_on_document_log));

create function automation.action_on_document_log_pending(
  action_on_document_log automation.action_on_document_log
) returns boolean as $$
  select not automation.action_on_document_log_errored(action_on_document_log)
  and not automation.action_on_document_log_success(action_on_document_log)
$$ language sql immutable strict;
comment on function automation.action_on_document_log_pending is '@notNull';
create index automation_action_on_document_log__pending_idx on automation.action_on_document_log (automation.action_on_document_log_pending(action_on_document_log));

----

create function automation.create_job_for_action_on_document_log()
returns trigger as $$
declare
  action_log automation.action_on_document_log;
  action_workflow_id uuid;
begin
  action_log := new;

  if exists (select from worker.job
    where job."type" = 'AUTOMATION_ACTION_ON_DOCUMENT'
    and payload->>'LogID' = action_log.id::text)
  then
    raise exception 'Job already created for action on document log with ID %.', action_log.id;
  end if;

  select workflow_id into action_workflow_id
  from automation.action
  where id = action_log.action_id;

  insert into worker.job ("type", payload, priority, start_at, origin)
  values (
    'AUTOMATION_ACTION_ON_DOCUMENT',
    jsonb_build_object(
      'LogID', action_log.id,
      -- unused by the actual worker, but helpful for dashboard's overview
      'CausedBy', (select coalesce(email, id::text) from public.user where id = action_log.created_by),
      'DocumentID', action_log.document_id,
      'Workflow', jsonb_build_object(
        'ID', action_workflow_id,
        'TriggerType', (select trigger_type from automation.workflow where id = action_workflow_id),
        'Name', (select name from automation.workflow where id = action_workflow_id)
      ),
      'ActionID', action_log.action_id
    ),
    100, -- 1000 is for source-file processing jobs
    action_log.created_at, -- try coercing the job worker to run actions in order
    'automation.create_job_for_action_on_document_log()'
  );

  return null;
end
$$ language plpgsql volatile security definer;

create trigger automation_action_on_document_insert_trigger
  after insert on automation.action_on_document_log
  for each row
  execute procedure automation.create_job_for_action_on_document_log();

create function automation.check_running_jobs_for_action_on_document_log()
returns trigger as $$
declare
  action_log automation.action_on_document_log;
begin
  action_log := old;

  if exists (select from worker.job
    where job."type" = 'AUTOMATION_ACTION_ON_DOCUMENT'
    and payload->>'LogID' = action_log.id::text)
  then
    raise exception 'Cannot delete the action log % because its job is running.', action_log.id;
  end if;

  return action_log;
end
$$ language plpgsql volatile security definer;

create trigger automation_action_on_document_delete_trigger
  before delete on automation.action_on_document_log
  for each row
  execute procedure automation.check_running_jobs_for_action_on_document_log();
