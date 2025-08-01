create table automation.action (
  id uuid primary key default uuid_generate_v4(),

  workflow_id     uuid not null references automation.workflow(id) on delete cascade,
  after_action_id uuid references automation.action(id) on delete cascade, -- chain multiple actions to run in series

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on automation.action to domonda_user;
grant select on automation.action to domonda_wg_user;

create unique index automation_only_one_root_action_per_workflow on automation.action (workflow_id) where (after_action_id is null);

create index automation_action_workflow_id_idx on automation.action (workflow_id);
create index automation_action_after_action_id_idx on automation.action (after_action_id);

create function automation.action_index(
  action automation.action
) returns int as $$
  with recursive action_chain as (
    select action.*

    union

    select a_action.*
    from action_chain, automation.action as a_action
    where action_chain.after_action_id = a_action.id
  )
  select
    count(1)::int - 1 -- indexes start with 0
  from action_chain;
$$ language sql stable strict;
comment on function automation.action_index is E'@notNull\nThe position of the action in the workflow following the action chain. Indexes start with zero (0).';

create function automation.action_no_other_actions(
  action automation.action
) returns boolean as $$
  select not exists(select from automation.action as a_action
    where a_action.id <> action.id
    and a_action.workflow_id = action.workflow_id)
$$ language sql stable strict;
comment on function automation.action_no_other_actions is E'@notNull\nAre there more actions in the workflow besides this one?';

create function automation.cascade_action_delete() returns trigger as $$
begin
  -- all action types have `action_id` as the PK
  delete from automation.action where id = old.action_id;
  return null;
end
$$ language plpgsql volatile;

----

create table automation.action_set_document_workflow_step (
  action_id uuid primary key references automation.action(id) on delete cascade,

  document_workflow_step_id uuid references public.document_workflow_step(id) on delete cascade,

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on automation.action_set_document_workflow_step to domonda_user;
grant select on automation.action_set_document_workflow_step to domonda_wg_user;

create trigger automation_action_set_document_workflow_step_delete
  after delete
  on automation.action_set_document_workflow_step
  for each row
  execute procedure automation.cascade_action_delete();

----

create table automation.action_create_direct_document_approval_request (
  action_id uuid primary key references automation.action(id) on delete cascade,

  approver_id uuid not null references public.user(id) on delete cascade,

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on automation.action_create_direct_document_approval_request to domonda_user;
grant select on automation.action_create_direct_document_approval_request to domonda_wg_user;

create trigger automation_action_create_dir_doc_appr_req_delete
  after delete
  on automation.action_create_direct_document_approval_request
  for each row
  execute procedure automation.cascade_action_delete();

----

create type automation.action_type as enum (
  'SET_DOCUMENT_WORKFLOW_STEP',
  'CREATE_DIRECT_DOCUMENT_APPROVAL_REQUEST'
);

create function automation.action_type(
  action automation.action
) returns automation.action_type as $$
  select (case
    when exists (select from automation.action_set_document_workflow_step where action_id = action.id)
    then 'SET_DOCUMENT_WORKFLOW_STEP'
    when exists (select from automation.action_create_direct_document_approval_request where action_id = action.id)
    then 'CREATE_DIRECT_DOCUMENT_APPROVAL_REQUEST'
    else null -- no subaction specified
  end)::automation.action_type
$$ language sql stable strict;
