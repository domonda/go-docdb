create function public.find_document_workflow_in_client_company(
  document_workflow_id uuid,
  client_company_id    uuid
) returns public.document_workflow as $$
  select document_workflow.*
  from public.document_workflow
  where document_workflow.client_company_id = find_document_workflow_in_client_company.client_company_id
  and document_workflow.name = (select src.name from public.document_workflow as src
    where src.id = find_document_workflow_in_client_company.document_workflow_id)
  and (
    select count(1) from public.document_workflow_step
    where document_workflow_step.workflow_id = document_workflow.id
  ) = (
    select count(1) from public.document_workflow_step
    where document_workflow_step.workflow_id = find_document_workflow_in_client_company.document_workflow_id
  )
$$ language sql stable strict;

create function public.find_document_workflow_step_in_client_company(
  document_workflow_step_id uuid,
  client_company_id         uuid
) returns public.document_workflow_step as $$
  select document_workflow_step.*
  from public.document_workflow_step
    inner join public.document_workflow on document_workflow.id = document_workflow_step.workflow_id
  where document_workflow.client_company_id = find_document_workflow_step_in_client_company.client_company_id
  and public.document_workflow_step_full_name(document_workflow_step) = (select public.document_workflow_step_full_name(src)
    from public.document_workflow_step as src
    where src.id = find_document_workflow_step_in_client_company.document_workflow_step_id)
$$ language sql stable strict;
