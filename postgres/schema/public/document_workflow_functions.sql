create function private.update_workflow_step_for_document(
    document_id               uuid,
    document_workflow_step_id uuid = null
) returns public.document as
$$
    update public.document
        set workflow_step_id=update_workflow_step_for_document.document_workflow_step_id, updated_at=now()
    where (id = update_workflow_step_for_document.document_id)
    returning *
$$
language sql volatile security definer;

----

create function public.update_workflow_step_for_document(
    document_id               uuid,
    document_workflow_step_id uuid = null
) returns public.document as
$$
declare
    next_document record;
begin
    -- if the user doesn't have access to the current step, he shouldn't be able to push the document anywhere
    if not exists (select from document
        where id = document_id
        and public.document_can_current_user_change(document))
    then
        raise exception 'Forbidden';
    end if;

    -- if the new document workflow step is null OR prev/next step of the currently active step (following the "index")
    if (
        with dws as (
            select dws.* from public.document as d
                inner join public.document_workflow_step as dws on (dws.id = d.workflow_step_id)
            where (d.id = update_workflow_step_for_document.document_id)
        )
        select
            (
                update_workflow_step_for_document.document_workflow_step_id is null
            ) or (
                prev_step.id = update_workflow_step_for_document.document_workflow_step_id
            ) or (
                next_step.id = update_workflow_step_for_document.document_workflow_step_id
            )
        from
            dws,
            public.document_workflow_step_protected_previous_step(dws) as prev_step,
            public.document_workflow_step_protected_next_step(dws) as next_step
    ) then

        -- the function below is defined as `SECURITY DEFINER` so that the user can
        -- perform the action even if he does not have access to the prev/next step
        perform private.update_workflow_step_for_document(update_workflow_step_for_document.document_id, update_workflow_step_for_document.document_workflow_step_id);

        -- we re-SELECT the document and return it. if the user does not have access to
        -- the next document, the SELECT will return NULL
        select * into next_document from public.document where (id = update_workflow_step_for_document.document_id);

    else

        -- perform a regular update if the new document workflow step is neither the prev/next step
        update public.document
            set workflow_step_id=update_workflow_step_for_document.document_workflow_step_id, updated_at=now()
        where (id = update_workflow_step_for_document.document_id)
        returning * into next_document;

    end if;

    return next_document;
end;
$$
language plpgsql volatile;

comment on function public.update_workflow_step_for_document is 'Sets the `DocumentWorkflowStep` for the `Document`.';

----

create function public.update_workflow_step_for_documents(
    document_ids              uuid[],
    document_workflow_step_id uuid = null
) returns setof public.document as $$
    select public.update_workflow_step_for_document(
        document.id,
        update_workflow_step_for_documents.document_workflow_step_id
    )
    from public.document
    where document.id = any(document_ids)
$$ language sql volatile;
