create type automation.workflow_trigger_type as enum (
  'DOCUMENT_READY',
  'DOCUMENT_CHANGED',
  'DOCUMENT_WORKFLOW_CHANGED',
  'DOCUMENT_APPROVAL_APPROVED'
  -- TODO: 'DOCUMENT_BOOKED'
  -- TODO: 'DOCUMENT_EXPORTED'
  -- TODO: 'DOCUMENT_PAID'
  -- TODO: 'DOCUMENT_NEW_TAG'
  -- TODO: 'DOCUMENT_NEW_COST_CENTER'
  -- TODO: 'DOCUMENT_NEW_COST_UNIT'
);

create table automation.workflow (
  id uuid primary key default uuid_generate_v4(),

  client_company_id uuid not null references public.client_company(company_id) on delete cascade,

  enabled boolean not null default false, -- have the user manually enable for awareness

  trigger_type automation.workflow_trigger_type not null,

  name non_empty_text not null,

  created_by uuid not null
    default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
    references public.user(id) on delete set default,
  updated_by uuid references public.user(id) on delete set null, -- TODO: if the user that did the update gets deleted, this column will be `null`

  -- TODO: when _any_ of the related tables change, update the updated_by here

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on automation.workflow to domonda_user;
grant select on automation.workflow to domonda_wg_user;

create index automation_workflow_client_company_id_idx on automation.workflow (client_company_id);
create index automation_workflow_enabled_idx on automation.workflow (enabled);
create index automation_workflow_trigger_type_idx on automation.workflow (trigger_type);

----

create table automation.workflow_first_group (
  id uuid primary key default uuid_generate_v4(),

  client_company_id uuid not null references public.client_company(company_id) on delete cascade

  -- TODO: make sure all workflows belonging in the group are from the same client (there's a check in automation.run() though)
);

comment on table automation.workflow_first_group is '"First workflow groups" run just _one_ passing belonging workflow checked in ascending order by the `index`.';

grant all on automation.workflow_first_group to domonda_user;
grant select on automation.workflow_first_group to domonda_wg_user;

create index automation_workflow_first_group_client_company_id_idx on automation.workflow_first_group (client_company_id);

create table automation.workflow_first_group_workflow (
  id uuid primary key default uuid_generate_v4(),

  group_id    uuid not null references automation.workflow_first_group(id) on delete cascade,
  workflow_id uuid not null references automation.workflow(id) on delete restrict, -- first delete the group (we dont want to break groups by removing just one item)
  unique(group_id, workflow_id),

  index int not null check(index >= 0),
  unique(group_id, index)
);

grant all on automation.workflow_first_group_workflow to domonda_user;
grant select on automation.workflow_first_group_workflow to domonda_wg_user;

create index automation_workflow_first_group_workflow_group_id_idx on automation.workflow_first_group_workflow (group_id);
create index automation_workflow_first_group_workflow_workflow_id_idx on automation.workflow_first_group_workflow (workflow_id);
create index automation_workflow_first_group_workflow_index_idx on automation.workflow_first_group_workflow (index);
