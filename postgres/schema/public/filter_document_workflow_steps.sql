create function public.filter_document_workflow_steps(
  client_company_id uuid,
  workflow_id       uuid = null,
  search_text       text = null
) returns setof public.document_workflow_step as $$
  select document_workflow_step.* from public.document_workflow_step
    inner join public.document_workflow as document_workflow on document_workflow.id = document_workflow_step.workflow_id
  where document_workflow.client_company_id = filter_document_workflow_steps.client_company_id
  and (filter_document_workflow_steps.workflow_id is null)
    or (filter_document_workflow_steps.workflow_id = document_workflow.id)
  and (coalesce(trim(filter_document_workflow_steps.search_text), '') = '')
    or (
      (document_workflow.name ilike '%' || filter_document_workflow_steps.search_text || '%')
      or (document_workflow_step.name ilike '%' || filter_document_workflow_steps.search_text || '%'))
  order by
    document_workflow_step.index,
    document_workflow_step.name
$$ language sql stable;

comment on function public.filter_document_workflow_steps is 'Filters for `DocumentWorkflowStep`s.';
