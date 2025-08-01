create function public.create_wizard_workflow_and_approvals(
  client_company_id uuid,
  payload json -- must match domonda-app/src/modules/Wizard/WizardWorkflowWithApprovals/WizardWorkflowWithApprovals.tsx@FormValues
) returns public.wizard_workflow_and_approvals as $$
declare
  created_wizard_workflow_and_approvals public.wizard_workflow_and_approvals;

  created_document_workflow public.document_workflow;

  document_workflow_steps     public.document_workflow_step[]; -- BEWARE sql arrays start with 1 (and not with 0)
  prev_document_workflow_step public.document_workflow_step;
  curr_document_workflow_step public.document_workflow_step;
  next_document_workflow_step public.document_workflow_step;

  curr_workflow automation.workflow;
  curr_skip_workflow automation.workflow;
  curr_filter_group_id uuid;
  curr_action automation.action;
  next_action automation.action; -- for assembling chained actions with after_action_id

  curr_workflow_first_group_id uuid;

  complete_payload_steps json;

  payload_step_index int;
  payload_step json;
  payload_step_filter_group json;
  payload_step_filter json;
  payload_step_approver json;
begin
  -- all/complete workflow & approvals steps (append the final "approved" step)
  complete_payload_steps := (
    (payload->'steps')::jsonb ||
    ('{ "isFinal": true, "name": "' || (case when private.current_user_language() = 'de' then 'Freigegeben' else 'Approved' end) || '" }')::jsonb
  )::json;

  -- prepare workflow and it's steps (necessary for looking for previous and next steps)
  insert into public.document_workflow (id, client_company_id, name, is_automatic)
  values (uuid_generate_v4(), create_wizard_workflow_and_approvals.client_company_id, payload->>'name', true)
  returning * into created_document_workflow;

  payload_step_index := 0;
  for payload_step in select * from json_array_elements(complete_payload_steps)
  loop
    insert into public.document_workflow_step (id, workflow_id, index, name)
    values (uuid_generate_v4(), created_document_workflow.id, payload_step_index+1, payload_step->>'name')
    returning * into curr_document_workflow_step;

    document_workflow_steps := array_append(document_workflow_steps, curr_document_workflow_step);

    payload_step_index := payload_step_index + 1;
  end loop;

  -- and then do the wizard's setup
  insert into public.wizard_workflow_and_approvals (client_company_id, name, document_workflow_id, payload, created_by)
  values (create_wizard_workflow_and_approvals.client_company_id, created_document_workflow.name, created_document_workflow.id, create_wizard_workflow_and_approvals.payload, private.current_user_id())
  returning * into created_wizard_workflow_and_approvals;

  payload_step_index := 0;
  for payload_step in select * from json_array_elements(complete_payload_steps)
  loop
    prev_document_workflow_step = document_workflow_steps[(payload_step_index+1) - 1];
    curr_document_workflow_step = document_workflow_steps[(payload_step_index+1)];
    next_document_workflow_step = document_workflow_steps[(payload_step_index+1) + 1];

    if payload_step_index = 0
    then
      -- the initiator step
      insert into automation.workflow (client_company_id, enabled, trigger_type, name, created_by)
      values (
        create_wizard_workflow_and_approvals.client_company_id,
        true,
        'DOCUMENT_CHANGED',
        trim(created_document_workflow.name) || ' ' || trim(curr_document_workflow_step.name),
        private.current_user_id()
      )
      returning * into curr_workflow;

      -- when base + user specified filters pass
      if payload_step->'filterGroups'->0->0 is null -- filterGroups[0][0] because a user might've supplied an empty filter group
      then
        -- user provided no filters, only set up the base filter

        -- when in no workflow
        insert into automation.workflow_trigger_filter_group (workflow_id)
        values (curr_workflow.id)
        returning id into curr_filter_group_id;
        insert into automation.workflow_trigger_filter_group_document_in_workflow_step (group_id, equality, document_workflow_step_id)
        values (curr_filter_group_id, 'EQUAL_TO', null);
      else
        -- user provided filters, apply base filter and then the user specified
        -- each group must have the same base filter (because separate groups are OR-ed)

        for payload_step_filter_group in select * from json_array_elements(payload_step->'filterGroups')
        loop
          insert into automation.workflow_trigger_filter_group (workflow_id)
          values (curr_workflow.id)
          returning id into curr_filter_group_id;

          -- when in no workflow
          insert into automation.workflow_trigger_filter_group_document_in_workflow_step (group_id, equality, document_workflow_step_id)
          values (curr_filter_group_id, 'EQUAL_TO', null);

          for payload_step_filter in select * from json_array_elements(payload_step_filter_group)
          loop
            case payload_step_filter->>'type'
            when 'DOCUMENT_TYPE' then
              insert into automation.workflow_trigger_filter_group_document_of_category_type (group_id, equality, "type")
              values (
                curr_filter_group_id,
                (payload_step_filter->>'operator')::automation.equality_operator,
                (payload_step_filter->>'value')::public.document_type
              );
            when 'PARTNER' then
              insert into automation.workflow_trigger_filter_group_document_with_partner (group_id, equality, partner_company_id)
              values (
                curr_filter_group_id,
                (payload_step_filter->>'operator')::automation.equality_operator,
                (payload_step_filter->'value'->>'rowId')::uuid
              );
            when 'TOTAL' then
              insert into automation.workflow_trigger_filter_group_invoice_with_total (group_id, comparison, total)
              values (
                curr_filter_group_id,
                (payload_step_filter->>'operator')::automation.comparison_operator,
                (payload_step_filter->>'value')::float8
              );
            else
              raise exception 'Unknown filter type %', payload_step_filter->>'type';
            end case;
          end loop;
        end loop;
      end if;

      -- put in current workflow step
      insert into automation.action (workflow_id)
      values (curr_workflow.id)
      returning * into curr_action;
      insert into automation.action_set_document_workflow_step (action_id, document_workflow_step_id)
      values (curr_action.id, curr_document_workflow_step.id);

      -- make sure there are approvers for this step
      if payload_step->'approvers'->0 is null
      then
        -- TODO: translate for german users
        raise exception 'At least one approver is required for each step. Step % has no approvers.', (payload_step_index + 1);
      end if;

      -- and issue approval request(s)
      for payload_step_approver in select * from json_array_elements(payload_step->'approvers')
      loop
        insert into automation.action (workflow_id, after_action_id)
        values (curr_workflow.id, curr_action.id)
        returning * into next_action;
        insert into automation.action_create_direct_document_approval_request (action_id, approver_id)
        values (next_action.id, (payload_step_approver->>'rowId')::uuid);

        -- necessary for chaining when multiple approvals get issued
        curr_action = next_action;
      end loop;

      -- link with wizard
      insert into public.wizard_workflow_and_approvals_step (wizard_workflow_and_approvals_id, document_workflow_step_id, automation_workflow_id)
      values (created_wizard_workflow_and_approvals.id, curr_document_workflow_step.id, curr_workflow.id);

      -- finally proceed with other steps
      payload_step_index := payload_step_index + 1;
      continue;
    end if;

    -- all other steps (including the approved (final) step)
    insert into automation.workflow (client_company_id, enabled, trigger_type, name, created_by)
    values (
      create_wizard_workflow_and_approvals.client_company_id,
      true,
      'DOCUMENT_APPROVAL_APPROVED',
      (case when private.current_user_language() = 'de' then 'Freigegeben ' else 'Approved ' end ||
        trim(created_document_workflow.name) || ' ' || trim(prev_document_workflow_step.name)),
      private.current_user_id()
    )
    returning * into curr_workflow;

    insert into automation.workflow_trigger_filter_group (workflow_id)
    values (curr_workflow.id)
    returning id into curr_filter_group_id;

    -- when in the previous step
    insert into automation.workflow_trigger_filter_group_document_in_workflow_step (group_id, equality, document_workflow_step_id)
    values (curr_filter_group_id, 'EQUAL_TO', prev_document_workflow_step.id);

    -- and approved by previous step's approver(s)
    insert into automation.workflow_trigger_filter_group_direct_document_approval_approved (group_id, approver_id)
    select curr_filter_group_id, (value->>'rowId')::uuid from json_array_elements(payload->'steps'->(payload_step_index-1)->'approvers');

    -- put in current workflow step
    insert into automation.action (workflow_id)
    values (curr_workflow.id)
    returning * into curr_action;
    insert into automation.action_set_document_workflow_step (action_id, document_workflow_step_id)
    values (curr_action.id, curr_document_workflow_step.id);

    -- link with wizard
    insert into public.wizard_workflow_and_approvals_step (wizard_workflow_and_approvals_id, document_workflow_step_id, automation_workflow_id)
    values (created_wizard_workflow_and_approvals.id, curr_document_workflow_step.id, curr_workflow.id);

    -- if final step, we're done - it will be reached through the workflow of the previous step
    if payload_step->>'isFinal' is not distinct from 'true'
    then
      exit;
    end if;

    ----

    -- approval issuer for all other steps (including the approved (final) step)
    insert into automation.workflow (client_company_id, enabled, trigger_type, name, created_by)
    values (
      create_wizard_workflow_and_approvals.client_company_id,
      true,
      'DOCUMENT_WORKFLOW_CHANGED',
      (case when private.current_user_language() = 'de' then 'Workflowsschritt geändert ' else 'Workflow step changed ' end ||
        trim(created_document_workflow.name) || ' ' || trim(curr_document_workflow_step.name)),
      private.current_user_id()
    )
    returning * into curr_workflow;

    -- when base + user specified filters pass
    if payload_step->'filterGroups'->0->0 is null -- filterGroups[0][0] because a user might've supplied an empty filter group
    then
      -- user provided no filters, only set up the base filter

      -- when in the current step
      insert into automation.workflow_trigger_filter_group (workflow_id)
      values (curr_workflow.id)
      returning id into curr_filter_group_id;
      insert into automation.workflow_trigger_filter_group_document_in_workflow_step (group_id, equality, document_workflow_step_id)
      values (curr_filter_group_id, 'EQUAL_TO', curr_document_workflow_step.id);
    else
      -- user provided filters, apply base filters and then the user specified
      -- each group must have the same base filters (because separate groups are OR-ed)

      for payload_step_filter_group in select * from json_array_elements(payload_step->'filterGroups')
      loop
        insert into automation.workflow_trigger_filter_group (workflow_id)
        values (curr_workflow.id)
        returning id into curr_filter_group_id;

        -- when in the current step
        insert into automation.workflow_trigger_filter_group_document_in_workflow_step (group_id, equality, document_workflow_step_id)
        values (curr_filter_group_id, 'EQUAL_TO', curr_document_workflow_step.id);

        -- and when user specified filters pass
        for payload_step_filter in select * from json_array_elements(payload_step_filter_group)
        loop
          case payload_step_filter->>'type'
          when 'DOCUMENT_TYPE' then
            insert into automation.workflow_trigger_filter_group_document_of_category_type (group_id, equality, "type")
            values (
              curr_filter_group_id,
              (payload_step_filter->>'operator')::automation.equality_operator,
              (payload_step_filter->>'value')::public.document_type
            );
          when 'PARTNER' then
            insert into automation.workflow_trigger_filter_group_document_with_partner (group_id, equality, partner_company_id)
            values (
              curr_filter_group_id,
              (payload_step_filter->>'operator')::automation.equality_operator,
              (payload_step_filter->'value'->>'rowId')::uuid
            );
          when 'TOTAL' then
            insert into automation.workflow_trigger_filter_group_invoice_with_total (group_id, comparison, total)
            values (
              curr_filter_group_id,
              (payload_step_filter->>'operator')::automation.comparison_operator,
              (payload_step_filter->>'value')::float8
            );
          else
            raise exception 'Unknown filter type %', payload_step_filter->>'type';
          end case;
        end loop;
      end loop;
    end if;

    -- make sure there are approvers for this step
    if payload_step->'approvers'->0 is null
    then
      -- TODO: translate for german users
      raise exception 'At least one approver is required for each step. Step % has no approvers.', (payload_step_index + 1);
    end if;

    -- avoid accidentally chaining unrelated actions
    curr_action := null;

    -- and issue approval request(s)
    for payload_step_approver in select * from json_array_elements(payload_step->'approvers')
    loop
      insert into automation.action (workflow_id, after_action_id)
      values (curr_workflow.id, curr_action.id)
      returning * into next_action;
      insert into automation.action_create_direct_document_approval_request (action_id, approver_id)
      values (next_action.id, (payload_step_approver->>'rowId')::uuid);

      -- necessary for chaining when multiple approvals get issued
      curr_action = next_action;
    end loop;

    -- link with wizard
    insert into public.wizard_workflow_and_approvals_step (wizard_workflow_and_approvals_id, document_workflow_step_id, automation_workflow_id)
    values (created_wizard_workflow_and_approvals.id, curr_document_workflow_step.id, curr_workflow.id);

    ----

    -- if user specified filters dont pass - we want to SKIP the step
    if payload_step->'filterGroups'->0->0 is not null
    then
      -- use the "first workflow group" that runs just _one_ belonging workflow by index in ascending order (see automation.run())
      insert into automation.workflow_first_group (client_company_id)
      values (create_wizard_workflow_and_approvals.client_company_id)
      returning id into curr_workflow_first_group_id;

      -- first try running user's workflow
      insert into automation.workflow_first_group_workflow (group_id, workflow_id, index)
      values (curr_workflow_first_group_id, curr_workflow.id, 0);

      -- the skip workflow
      insert into automation.workflow (client_company_id, enabled, trigger_type, name, created_by)
      values (
        create_wizard_workflow_and_approvals.client_company_id,
        true,
        curr_workflow.trigger_type,
        (case when private.current_user_language() = 'de' then 'Überspringen ' else 'Skip ' end ||
        trim(created_document_workflow.name) || ' ' || trim(curr_document_workflow_step.name)),
        private.current_user_id()
      )
      returning * into curr_skip_workflow;

      -- when in the current step (because we're skipping skipping it)
      insert into automation.workflow_trigger_filter_group (workflow_id)
      values (curr_skip_workflow.id)
      returning id into curr_filter_group_id;
      insert into automation.workflow_trigger_filter_group_document_in_workflow_step (group_id, equality, document_workflow_step_id)
      values (curr_filter_group_id, 'EQUAL_TO', curr_document_workflow_step.id);

      -- put in next workflow step
      insert into automation.action (workflow_id)
      values (curr_skip_workflow.id)
      returning * into curr_action;
      insert into automation.action_set_document_workflow_step (action_id, document_workflow_step_id)
      values (curr_action.id, next_document_workflow_step.id);

      -- alternatively try the skip workflow
      insert into automation.workflow_first_group_workflow (group_id, workflow_id, index)
      values (curr_workflow_first_group_id, curr_skip_workflow.id, 1);

      -- link with wizard
      insert into public.wizard_workflow_and_approvals_step (wizard_workflow_and_approvals_id, document_workflow_step_id, automation_workflow_id)
      values (created_wizard_workflow_and_approvals.id, next_document_workflow_step.id, curr_skip_workflow.id);
    end if;

    payload_step_index := payload_step_index + 1;
  end loop;

  return created_wizard_workflow_and_approvals;
end
$$ language plpgsql volatile strict;
