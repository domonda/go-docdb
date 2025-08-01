create function automation.check_workflow_trigger_filters(
  workflow automation.workflow,
  payload  jsonb, -- see automation.action_on_document_log.payload
  document public.document
) returns boolean as $$
declare
  curr_group_id uuid;
  filter record;
begin
  if not exists (select from automation.workflow_trigger_filter_group
    where workflow.id = workflow_trigger_filter_group.workflow_id)
  then
    -- no available filters exist, checks are not performed
    return null;
  end if;

  <<groups_loop>>
  for curr_group_id in (
    select id from automation.workflow_trigger_filter_group
    where workflow.id = workflow_trigger_filter_group.workflow_id
  )
  loop
    for filter in (
      select * from automation.workflow_trigger_filter_group_document_of_category_type
      where curr_group_id = group_id
    )
    loop
      continue groups_loop when not (automation.equality_operator_compare(
        filter.equality,
        filter."type"::text,
        (select document_type::text
        from public.document_category
        where document_category.id = document.category_id)
      ));
    end loop;

    for filter in (
      select * from automation.workflow_trigger_filter_group_document_in_workflow_step
      where curr_group_id = group_id
    )
    loop
      continue groups_loop when not (automation.equality_operator_compare(
        filter.equality,
        filter.document_workflow_step_id::text,
        document.workflow_step_id::text
      ));
    end loop;

    -- when approval filter is combined with trigger_type DOCUMENT_APPROVAL_APPROVED, it should filter at the MOMENT approvals happen
    -- if there are multiple approval filters, one has to be the current approver and the others previous approvers (see loop below)
    if workflow.trigger_type = 'DOCUMENT_APPROVAL_APPROVED'
    and payload->>'tg_table' = 'public.document_approval' -- just in case
    and exists (select from automation.workflow_trigger_filter_group_direct_document_approval_approved
      where curr_group_id = group_id)
    and not (exists (
      select from automation.workflow_trigger_filter_group_direct_document_approval_approved
      where curr_group_id = group_id
      and approver_id = (payload->'tg_row'->>'approver_id')::uuid)
    )
    then
      continue groups_loop;
    end if;
    for filter in (
      select * from automation.workflow_trigger_filter_group_direct_document_approval_approved
      where curr_group_id = group_id
    )
    loop
      continue groups_loop when not exists(
        -- approvals are chained: if X rejects approval to Y and then Y approves it, it is as if X approved it.
        with recursive approval_chain as (
          select document_approval.*
          from public.document_approval
            inner join public.document_approval_request on document_approval_request.id = document_approval.request_id
          where document_approval_request.document_id = document.id
          and document_approval_request.approver_id = filter.approver_id

          union

          select document_approval.*
          from approval_chain, public.document_approval
          where approval_chain.next_request_id = document_approval.request_id
        )
        select from approval_chain
        where approval_chain.next_request_id is null -- not rejected
        and not approval_chain.canceled
      );
    end loop;

    for filter in (
      select * from automation.workflow_trigger_filter_group_document_with_partner
      where curr_group_id = group_id
    )
    loop
      continue groups_loop when not (automation.equality_operator_compare(
        filter.equality,
        filter.partner_company_id::text,
        coalesce(
          (select invoice.partner_company_id::text from public.invoice
          where invoice.document_id = document.id),
          (select other_document.partner_company_id::text from public.other_document
          where other_document.document_id = document.id)
        )
      ));
    end loop;

    for filter in (
      select * from automation.workflow_trigger_filter_group_invoice_with_total
      where curr_group_id = group_id
    )
    loop
      continue groups_loop when not (automation.comparison_operator_compare_numeric(
        filter.comparison,
        filter.total::numeric,
        (select invoice.total::numeric from public.invoice
        where invoice.document_id = document.id)
      ));
    end loop;

    -- groups are OR-ed, if any of the group's pass - the check passes
    return true;
  end loop;

  -- no group passed, the check fails
  return false;
end
$$ language plpgsql stable;
comment on function automation.check_workflow_trigger_filters is '@omit';
