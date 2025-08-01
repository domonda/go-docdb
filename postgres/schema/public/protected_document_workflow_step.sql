create type public.protected_document_workflow_step as (
    id                uuid,
    workflow_id       uuid,
    index             int,
    name              text,
    index_with_name   text,
    full_name         text,
    created_by_wizard boolean,
    updated_at        timestamptz,
    created_at        timestamptz
);

comment on column public.protected_document_workflow_step.id is '@notNull';
comment on column public.protected_document_workflow_step.workflow_id is '@notNull';
comment on column public.protected_document_workflow_step.index is '@notNull';
comment on column public.protected_document_workflow_step.name is '@notNull';
comment on column public.protected_document_workflow_step.index_with_name is E'@notNull\nDerives the index + name of the step.';
comment on column public.protected_document_workflow_step.full_name is E'@notNull\nDerives the full name of the step (workflow + index + name).';
comment on column public.protected_document_workflow_step.created_by_wizard is '@notNull';
comment on column public.protected_document_workflow_step.updated_at is '@notNull';
comment on column public.protected_document_workflow_step.created_at is '@notNull';

comment on type public.protected_document_workflow_step is 'Protected `DocumentWorkflowStep` is a workflow step to which the user does not have access.';

create function public.document_workflow_step_protected_document_workflow_step(
    document_workflow_step public.document_workflow_step
) returns public.protected_document_workflow_step as $$
    select
        document_workflow_step.id,
        document_workflow_step.workflow_id,
        document_workflow_step.index,
        document_workflow_step.name,
        public.document_workflow_step_index_with_name(document_workflow_step),
        public.document_workflow_step_full_name(document_workflow_step),
        public.document_workflow_step_created_by_wizard(document_workflow_step),
        document_workflow_step.updated_at,
        document_workflow_step.created_at
$$ language sql stable strict security definer;
comment on function public.document_workflow_step_protected_document_workflow_step is '@notNull';

----

create function public.document_workflow_step_protected_previous_step(
    document_workflow_step public.document_workflow_step
) returns public.protected_document_workflow_step as $$
    select public.document_workflow_step_protected_document_workflow_step(dws)
    from document_workflow_step as dws
        left join document_workflow_step as curr_dws
        on curr_dws.id = document_workflow_step_protected_previous_step.document_workflow_step.id
    where dws.workflow_id = curr_dws.workflow_id
    and dws.id <> curr_dws.id
    and dws.index < curr_dws.index
    order by dws.index desc
    limit 1
$$ language sql stable
security definer; -- is used because the user might not have access to the previous step, but still needs to know what it is.

comment on function public.document_workflow_step_protected_previous_step IS 'Returns the previous `ProtectedDocumentWorkflowStep`, following the `index`.';

----

create function public.document_workflow_step_protected_next_step(
    document_workflow_step public.document_workflow_step
) returns public.protected_document_workflow_step as
$$
    select public.document_workflow_step_protected_document_workflow_step(dws)
    from document_workflow_step as dws
        left join document_workflow_step as curr_dws on (curr_dws.id = document_workflow_step_protected_next_step.document_workflow_step.id)
    where dws.workflow_id = curr_dws.workflow_id
    and  dws.id <> curr_dws.id
    and dws.index > curr_dws.index
    order by dws.index
    limit 1
$$
language sql stable
security definer; -- is used because the user might not have access to the next step, but still needs to know what it is.

comment on function public.document_workflow_step_protected_next_step is 'Returns the next `ProtectedDocumentWorkflowStep`, following the `index`.';

----

create function public.document_workflow_protected_steps_total_count(
    document_workflow public.document_workflow
) returns int as $$
    select count(1)::int from public.document_workflow_step
    where document_workflow_step.workflow_id = document_workflow.id
$$ language sql stable strict security definer;
comment on function public.document_workflow_protected_steps_total_count is '@notNull';

create function public.document_workflow_step_protected_row_number_sorted_by_index(
    document_workflow_step public.document_workflow_step
) returns int as $$
    with sorted_steps as (
        select
            id,
            row_number() over(order by "index")
        from document_workflow_step as dws
        where dws.workflow_id = document_workflow_step.workflow_id
    )
    select row_number::int from sorted_steps
    where sorted_steps.id = document_workflow_step.id
$$ language sql stable strict security definer;
comment on function public.document_workflow_step_protected_row_number_sorted_by_index is '@notNull';

create function public.review_group_document_protected_document_workflow_step(
  review_group_document public.review_group_document
) returns public.protected_document_workflow_step as $$
  select public.document_workflow_step_protected_document_workflow_step(document_workflow_step)
  from public.document_workflow_step
  where id = review_group_document.document_workflow_step_id
$$ language sql stable security definer;

----

create function private.filter_first_document_workflow_steps(
  client_company_id uuid,
  workflow_id       uuid = null,
  search_text       text = null
) returns setof public.document_workflow_step as $$
  select document_workflow_step.*
  from public.document_workflow_step
    inner join public.document_workflow as document_workflow on document_workflow.id = document_workflow_step.workflow_id
  where document_workflow.client_company_id = filter_first_document_workflow_steps.client_company_id
  and document_workflow_step.index = 1 -- hacky but fast, the first step mustnt always be at index 1 (but it almost always is!)
  and ((filter_first_document_workflow_steps.workflow_id is null)
    or (filter_first_document_workflow_steps.workflow_id = document_workflow.id))
  and ((coalesce(trim(filter_first_document_workflow_steps.search_text), '') = '')
    or (
      (document_workflow.name ilike '%' || filter_first_document_workflow_steps.search_text || '%')
      or (document_workflow_step.name ilike '%' || filter_first_document_workflow_steps.search_text || '%')))
$$ language sql stable security definer;

create function public.filter_protected_document_workflow_steps(
  client_company_id uuid,
  workflow_id       uuid = null,
  search_text       text = null
) returns setof public.protected_document_workflow_step as $$
  select public.document_workflow_step_protected_document_workflow_step(document_workflow_step)
  from (
    select * from private.filter_first_document_workflow_steps(filter_protected_document_workflow_steps.client_company_id, filter_protected_document_workflow_steps.workflow_id, filter_protected_document_workflow_steps.search_text)

    union -- without "all" because there might be duplicates

    select document_workflow_step.* from public.document_workflow_step
      inner join public.document_workflow as document_workflow on document_workflow.id = document_workflow_step.workflow_id
    where document_workflow.client_company_id = filter_protected_document_workflow_steps.client_company_id
    and not document_workflow.is_automatic -- documents can be put in 1st steps of automatic workflows ONLY. filter_first_document_workflow_steps will have the steps, so this subquery can safely omit automatic workflows altogether
    and ((filter_protected_document_workflow_steps.workflow_id is null)
      or (filter_protected_document_workflow_steps.workflow_id = document_workflow.id))
    and ((coalesce(trim(filter_protected_document_workflow_steps.search_text), '') = '')
      or (
        (document_workflow.name ilike '%' || filter_protected_document_workflow_steps.search_text || '%')
        or (document_workflow_step.name ilike '%' || filter_protected_document_workflow_steps.search_text || '%')))
  ) as document_workflow_step
  order by
    document_workflow_step.index,
    document_workflow_step.name
$$ language sql stable;
comment on function public.filter_protected_document_workflow_steps is 'Filters for `ProtectedDocumentWorkflowStep`s that the user can push a document into. Includes the results of `filterFirstDocumentWorkflowSteps`.';

----

create function public.client_company_sorted_protected_document_workflow_steps(
  client_company public.client_company
) returns setof public.protected_document_workflow_step as $$
  select * from public.filter_protected_document_workflow_steps(
    client_company_id=>client_company.company_id
  ) as protected_document_workflow_step
  -- no order by, already sorted bt the filter function
$$ language sql stable;
