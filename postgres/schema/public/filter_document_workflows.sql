create function public.filter_document_workflows(
  client_company_id uuid,
  search_text       text = null
) returns setof public.document_workflow as $$
  select * from public.document_workflow
  where client_company_id = filter_document_workflows.client_company_id
  and ((coalesce(trim(filter_document_workflows.search_text), '') = '')
    or (name ilike '%' || filter_document_workflows.search_text || '%'))
  order by name
$$ language sql stable;

comment on function public.filter_document_workflows is 'Filters for `DocumentWorkflow`s.';
