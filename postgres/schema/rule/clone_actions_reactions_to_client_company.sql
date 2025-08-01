-- TODO-db-210429 category mapping
-- TODO-db-210429 partner mapping
-- TODO-db-210429 cost-centers mapping
-- NOTE: workflow step full names must match exactly between the src and dest
-- NOTE: user group names must match exactly between the src and dest
create function rule.clone_actions_reactions_to_client_company(
    src_client_company_id  uuid,
    dest_client_company_id uuid
) returns setof rule.action_reaction as $$
declare
  cloned_action_reaction rule.action_reaction;
begin
  for cloned_action_reaction in (
    with src_action_reaction as (
      select
        action_reaction."trigger",
        action_reaction.action_id,
        action_reaction.reaction_id,
        action_reaction.disabled,
        action_reaction.sort_index,
        action_reaction.created_by,
        action_reaction.updated_by
      from rule.action_reaction
        inner join rule.action on action.id = action_reaction.action_id
      where action.client_company_id = src_client_company_id
    ), document_workflow_step_mapping as (
      with orig_steps as (
        select document_workflow_step.id from public.document_workflow_step
          inner join public.document_workflow on document_workflow.id = document_workflow_step.workflow_id
        where document_workflow.client_company_id = src_client_company_id
      )
      select
        hstore(array_agg(orig_steps.id::text), array_agg(document_workflow_step.id::text))
      from
        orig_steps,
        public.find_document_workflow_step_in_client_company(
          orig_steps.id,
          dest_client_company_id
        ) as document_workflow_step
    ), user_groups_mapping as (
      with src_group as (
        select user_group.* from public.user_group
        where user_group.client_company_id = src_client_company_id
      )
      select
        hstore(array_agg(src_group.id::text), array_agg(dest_group.id::text))
      from
        src_group,
        public.user_group as dest_group
      where dest_group.client_company_id = dest_client_company_id
      and src_group.name = dest_group.name
    ), action_mapping as (
      select
        hstore(array_agg(src.action_id::text), array_agg(dest_action.id::text))
      from
        (select distinct action_id from src_action_reaction) as src,
        document_workflow_step_mapping,
        rule.clone_action(
          src.action_id,
          dest_client_company_id,
          null, -- document_category_mapping
          document_workflow_step_mapping.hstore,
          null, -- partner_company_mapping
          null, -- client_company_cost_center_mapping
          null  -- real_estate_object_instance_mapping
        ) as dest_action
    ), reaction_mapping as (
      select
        hstore(array_agg(src.reaction_id::text), array_agg(dest_reaction.id::text))
      from
        (select distinct reaction_id from src_action_reaction) as src,
        document_workflow_step_mapping,
        user_groups_mapping,
        rule.clone_reaction(
          src.reaction_id,
          dest_client_company_id,
          document_workflow_step_mapping.hstore,
          null, -- client_company_tag_mapping
          user_groups_mapping.hstore
        ) as dest_reaction
    ), inserted_action_reaction as (
      insert into rule.action_reaction ("trigger", action_id, reaction_id, disabled, sort_index, created_by, updated_by)
      select
        src_action_reaction."trigger",
        (action_mapping.hstore->src_action_reaction.action_id::text)::uuid,
        (reaction_mapping.hstore->src_action_reaction.reaction_id::text)::uuid,
        src_action_reaction.disabled,
        src_action_reaction.sort_index,
        src_action_reaction.created_by,
        src_action_reaction.updated_by
      from
        src_action_reaction,
        action_mapping, reaction_mapping
      returning action_reaction.*
    )
    select * from inserted_action_reaction
  )
  loop
    -- disable if action or reaction needs attention
    if (select name like '%(NEEDS ATTENTION)' from rule.action
      where id = cloned_action_reaction.action_id)
    or (select name like '%(NEEDS ATTENTION)' from rule.reaction
      where id = cloned_action_reaction.reaction_id)
    then
      update rule.action_reaction
      set disabled=true
      where id = cloned_action_reaction.id
      returning * into cloned_action_reaction;
    end if;

    return next cloned_action_reaction;
  end loop;
end
$$ language plpgsql volatile;
