-- everything inside a group is AND-ed and groups together are OR-ed
create table automation.workflow_trigger_filter_group (
  id uuid primary key default uuid_generate_v4(),

  workflow_id uuid not null references automation.workflow(id) on delete cascade,

  created_at created_time not null
);

grant select, insert, delete on automation.workflow_trigger_filter_group to domonda_user;
grant select on automation.workflow_trigger_filter_group to domonda_wg_user;

create index workflow_trigger_filter_group_workflow_id_idx on automation.workflow_trigger_filter_group (workflow_id);

----

create table automation.workflow_trigger_filter_group_document_of_category_type (
  id uuid primary key default uuid_generate_v4(),

  group_id uuid not null references automation.workflow_trigger_filter_group(id) on delete cascade,

  equality automation.equality_operator not null,
  "type"   public.document_type not null,

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on automation.workflow_trigger_filter_group_document_of_category_type to domonda_user;
grant select on automation.workflow_trigger_filter_group_document_of_category_type to domonda_wg_user;

create index wf_trig_filter_doc_of_category_type_group_id_idx on automation.workflow_trigger_filter_group_document_of_category_type (group_id);

----

create table automation.workflow_trigger_filter_group_document_in_workflow_step (
  id uuid primary key default uuid_generate_v4(),

  group_id uuid not null references automation.workflow_trigger_filter_group(id) on delete cascade,

  equality                  automation.equality_operator not null,
  document_workflow_step_id uuid references public.document_workflow_step(id) on delete restrict,

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on automation.workflow_trigger_filter_group_document_in_workflow_step to domonda_user;
grant select on automation.workflow_trigger_filter_group_document_in_workflow_step to domonda_wg_user;

create index wf_trig_filter_doc_in_wf_step_document_workflow_step_id_idx on automation.workflow_trigger_filter_group_document_in_workflow_step (document_workflow_step_id);
create index wf_trig_filter_doc_in_wf_step_group_id_idx on automation.workflow_trigger_filter_group_document_in_workflow_step (group_id);

----

create table automation.workflow_trigger_filter_group_direct_document_approval_approved (
  id uuid primary key default uuid_generate_v4(),

  group_id uuid not null references automation.workflow_trigger_filter_group(id) on delete cascade,

  approver_id uuid not null references public.user(id) on delete restrict,

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on automation.workflow_trigger_filter_group_direct_document_approval_approved to domonda_user;
grant select on automation.workflow_trigger_filter_group_direct_document_approval_approved to domonda_wg_user;

create index wf_trig_filter_direct_doc_approval_approved_approver_id_idx on automation.workflow_trigger_filter_group_direct_document_approval_approved (approver_id);
create index wf_trig_filter_direct_doc_approval_approved_group_id_idx on automation.workflow_trigger_filter_group_direct_document_approval_approved (group_id);

----

create table automation.workflow_trigger_filter_group_document_with_partner (
  id uuid primary key default uuid_generate_v4(),

  group_id uuid not null references automation.workflow_trigger_filter_group(id) on delete cascade,

  equality           automation.equality_operator not null,
  partner_company_id uuid not null references public.partner_company(id) on delete restrict,
  -- TODO: should the partner_company_id be nullable? not often does the user want "when invoice doesnt have a partner - do something"

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on automation.workflow_trigger_filter_group_document_with_partner to domonda_user;
grant select on automation.workflow_trigger_filter_group_document_with_partner to domonda_wg_user;

create index wf_trig_filter_document_with_partner_group_id_idx on automation.workflow_trigger_filter_group_document_with_partner (group_id);
create index wf_trig_filter_document_with_partner_partner_company_id_idx on automation.workflow_trigger_filter_group_document_with_partner (partner_company_id);

----

create table automation.workflow_trigger_filter_group_invoice_with_total (
  id uuid primary key default uuid_generate_v4(),

  group_id uuid not null references automation.workflow_trigger_filter_group(id) on delete cascade,

  comparison automation.comparison_operator not null,
  total      float8 not null,
  -- TODO: should the total be nullable? not often does the user want "when invoice doesnt have a total - do something"

  updated_at updated_time not null,
  created_at created_time not null
);

grant all on automation.workflow_trigger_filter_group_invoice_with_total to domonda_user;
grant select on automation.workflow_trigger_filter_group_invoice_with_total to domonda_wg_user;

create index wf_trig_filter_invoice_with_total_group_id_idx on automation.workflow_trigger_filter_group_invoice_with_total (group_id);

----

create view automation.workflow_trigger_filter_group_filter as
  (
    select
      workflow_trigger_filter_group_document_of_category_type.id,
      workflow_id,
      group_id,
      'document_of_category_type' as "type",
      json_build_object(
        'equality', equality,
        'type', "type"
      ) as payload,
      workflow_trigger_filter_group_document_of_category_type.created_at
    from automation.workflow_trigger_filter_group_document_of_category_type
      inner join automation.workflow_trigger_filter_group on workflow_trigger_filter_group.id = workflow_trigger_filter_group_document_of_category_type.group_id
  ) union all (
    select
      workflow_trigger_filter_group_document_in_workflow_step.id,
      workflow_id,
      group_id,
      'document_in_workflow_step' as "type",
      json_build_object(
        'equality', equality,
        'document_workflow_step_id', "document_workflow_step_id"
      ) as payload,
      workflow_trigger_filter_group_document_in_workflow_step.created_at
    from automation.workflow_trigger_filter_group_document_in_workflow_step
      inner join automation.workflow_trigger_filter_group on workflow_trigger_filter_group.id = workflow_trigger_filter_group_document_in_workflow_step.group_id
  ) union all (
    select
      workflow_trigger_filter_group_direct_document_approval_approved.id,
      workflow_id,
      group_id,
      'direct_document_approval_approved' as "type",
      json_build_object(
        'approver_id', approver_id
      ) as payload,
      workflow_trigger_filter_group_direct_document_approval_approved.created_at
    from automation.workflow_trigger_filter_group_direct_document_approval_approved
      inner join automation.workflow_trigger_filter_group on workflow_trigger_filter_group.id = workflow_trigger_filter_group_direct_document_approval_approved.group_id
  ) union all (
    select
      workflow_trigger_filter_group_document_with_partner.id,
      workflow_id,
      group_id,
      'document_with_partner' as "type",
      json_build_object(
        'equality', equality,
        'partner_company_id', partner_company_id
      ) as payload,
      workflow_trigger_filter_group_document_with_partner.created_at
    from automation.workflow_trigger_filter_group_document_with_partner
      inner join automation.workflow_trigger_filter_group on workflow_trigger_filter_group.id = workflow_trigger_filter_group_document_with_partner.group_id
  ) union all (
    select
      workflow_trigger_filter_group_invoice_with_total.id,
      workflow_id,
      group_id,
      'invoice_with_total' as "type",
      json_build_object(
        'comparison', comparison,
        'total', total
      ) as payload,
      workflow_trigger_filter_group_invoice_with_total.created_at
    from automation.workflow_trigger_filter_group_invoice_with_total
      inner join automation.workflow_trigger_filter_group on workflow_trigger_filter_group.id = workflow_trigger_filter_group_invoice_with_total.group_id
  );

grant all on automation.workflow_trigger_filter_group_filter to domonda_user;
grant select on automation.workflow_trigger_filter_group_filter to domonda_wg_user;

comment on view automation.workflow_trigger_filter_group_filter is '@omit';
