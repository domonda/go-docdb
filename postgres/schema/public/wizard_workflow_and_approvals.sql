-- dont delete directly, please use the public.delete_wizard_workflow_and_approvals instead
create table public.wizard_workflow_and_approvals (
  id uuid primary key default uuid_generate_v4(),

  client_company_id uuid not null references public.client_company(company_id) on delete cascade,

  name non_empty_text not null,

  document_workflow_id uuid not null references public.document_workflow(id) on delete restrict,
  -- TODO: prevent editing workflow while in wizard

  payload json not null, -- the original wizard payload for revisiting the wizard setup

  created_by uuid not null references public.user(id) on delete restrict,
	created_at created_time not null
);

grant select, insert, delete on table public.wizard_workflow_and_approvals to domonda_user;

create index wizard_workflow_and_approvals_client_company_id_idx on public.wizard_workflow_and_approvals (client_company_id);
create index wizard_workflow_and_approvals_name_idx on public.wizard_workflow_and_approvals (name);
create index wizard_workflow_and_approvals_document_workflow_id_idx on public.wizard_workflow_and_approvals (document_workflow_id);

----

-- dont delete directly, please use the public.delete_wizard_workflow_and_approvals instead
create table public.wizard_workflow_and_approvals_step (
  id uuid primary key default uuid_generate_v4(),

  wizard_workflow_and_approvals_id uuid not null references public.wizard_workflow_and_approvals(id) on delete cascade,

  document_workflow_step_id uuid not null references public.document_workflow_step(id) on delete restrict,
  automation_workflow_id    uuid not null unique references automation.workflow(id) on delete restrict
);

grant select, insert, delete on table public.wizard_workflow_and_approvals_step to domonda_user;

create index wizard_wf_and_app_step_wizard_workflow_and_approvals_id_idx on public.wizard_workflow_and_approvals_step (wizard_workflow_and_approvals_id);
create index wizard_wf_and_app_step_document_workflow_step_id_idx on public.wizard_workflow_and_approvals_step (document_workflow_step_id);
create index wizard_wf_and_app_step_automation_workflow_id_idx on public.wizard_workflow_and_approvals_step (automation_workflow_id);

----

create function public.filter_wizard_workflow_and_approvals(
  client_company_id uuid,
  search_text text = null
) returns setof public.wizard_workflow_and_approvals as $$
  select * from public.wizard_workflow_and_approvals
  where wizard_workflow_and_approvals.client_company_id = filter_wizard_workflow_and_approvals.client_company_id
  and (filter_wizard_workflow_and_approvals.search_text is null
    or wizard_workflow_and_approvals.name ilike '%' || filter_wizard_workflow_and_approvals.search_text || '%')
  order by created_at desc -- newest on top
$$ language sql stable;

create function public.wizard_workflow_and_approvals_sorted_steps(
  wizard_workflow_and_approvals public.wizard_workflow_and_approvals
) returns setof public.wizard_workflow_and_approvals_step as $$
  select wizard_workflow_and_approvals_step.* from public.wizard_workflow_and_approvals_step
    inner join public.document_workflow_step on document_workflow_step.id = wizard_workflow_and_approvals_step.document_workflow_step_id
  where wizard_workflow_and_approvals_step.wizard_workflow_and_approvals_id = wizard_workflow_and_approvals.id
  order by document_workflow_step.index asc -- lowest to highest, like in wizard
$$ language sql stable strict;

create function public.document_workflow_created_by_wizard(
  document_workflow public.document_workflow
) returns boolean as $$
  select exists(select from public.wizard_workflow_and_approvals
    where document_workflow_id = document_workflow.id)
$$ language sql stable strict;
comment on function public.document_workflow_created_by_wizard is '@notNull';

create function public.document_workflow_step_created_by_wizard(
  document_workflow_step public.document_workflow_step
) returns boolean as $$
  select exists(select from public.wizard_workflow_and_approvals_step
    where document_workflow_step_id = document_workflow_step.id)
$$ language sql stable strict;
comment on function public.document_workflow_step_created_by_wizard is '@notNull';

----

create function private.delete_automation_action_on_document_log(
  id uuid
) returns automation.action_on_document_log as $$
  delete from automation.action_on_document_log
  where action_on_document_log.id = delete_automation_action_on_document_log.id
  returning *
$$ language sql volatile strict security definer;

create function public.delete_wizard_workflow_and_approvals(
  id uuid
) returns public.wizard_workflow_and_approvals as $$
declare
  is_demo_client boolean; -- delete all usage references before deleting the wizards for demo users

  wizard_workflow_and_approvals public.wizard_workflow_and_approvals;
  wizard_workflow_and_approvals_step public.wizard_workflow_and_approvals_step;
begin
  select * into wizard_workflow_and_approvals
  from public.wizard_workflow_and_approvals as to_del_wizard_workflow_and_approvals
  where to_del_wizard_workflow_and_approvals.id = delete_wizard_workflow_and_approvals.id;

  is_demo_client := public.get_client_company_status(wizard_workflow_and_approvals.client_company_id) = 'DEMO';

  if is_demo_client then
    -- unset all documents in wizards workflows
    -- we do this first to avoid triggering automations once workflow_trigger_filter_group_document_in_workflow_step get deleted
    update public.document
    set workflow_step_id=null, updated_at=now()
    from public.document_workflow_step
    where document_workflow_step.workflow_id = wizard_workflow_and_approvals.document_workflow_id
    and document_workflow_step.id = document.workflow_step_id;
  end if;

  for wizard_workflow_and_approvals_step in (select * from public.wizard_workflow_and_approvals_step as to_del_wizard_workflow_and_approvals_step
    where to_del_wizard_workflow_and_approvals_step.wizard_workflow_and_approvals_id = wizard_workflow_and_approvals.id)
  loop
    if is_demo_client then
      -- delete action logs to allow deleting automations
      perform private.delete_automation_action_on_document_log(action_on_document_log.id)
        from automation.action_on_document_log
          inner join automation.action on action.id = action_on_document_log.action_id
      where action.workflow_id = wizard_workflow_and_approvals_step.automation_workflow_id;
    end if;

    delete from public.wizard_workflow_and_approvals_step as to_del_wizard_workflow_and_approvals_step
    where wizard_workflow_and_approvals_step.id = to_del_wizard_workflow_and_approvals_step.id;

    delete from automation.workflow_first_group_workflow
    where workflow_first_group_workflow.workflow_id = wizard_workflow_and_approvals_step.automation_workflow_id;

    delete from automation.workflow
    where workflow.id = wizard_workflow_and_approvals_step.automation_workflow_id;

    -- even though we've deleted the automation.workflow, we must delete all filters for this step because other workflows might depend on it
    delete from automation.workflow_trigger_filter_group_document_in_workflow_step
    where workflow_trigger_filter_group_document_in_workflow_step.document_workflow_step_id = wizard_workflow_and_approvals_step.document_workflow_step_id;

    -- NOT NECESSARY because delete document_workflow from below will cascade to it's steps
    -- delete from public.document_workflow_step
    -- where document_workflow_step.id = wizard_workflow_and_approvals_step.document_workflow_step_id;

    -- TODO: delete all approval requests issued as a part of the automation workflow for demo clients
  end loop;

  delete from wizard_workflow_and_approvals as to_del_wizard_workflow_and_approvals
  where to_del_wizard_workflow_and_approvals.id = wizard_workflow_and_approvals.id;

  delete from public.document_workflow
  where document_workflow.id = wizard_workflow_and_approvals.document_workflow_id;

  -- drop dangling first workflow groups
  delete from automation.workflow_first_group
  where workflow_first_group.client_company_id = wizard_workflow_and_approvals.client_company_id
  and not exists (select from automation.workflow_first_group_workflow
    where group_id = workflow_first_group.id);

  return wizard_workflow_and_approvals;
end
$$ language plpgsql volatile strict;
