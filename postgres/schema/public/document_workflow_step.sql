create table public.document_workflow_step (
    id uuid primary key,

    workflow_id uuid not null references public.document_workflow(id) on delete cascade,
    index       int not null check(index >= 1), -- must start with 1 because the ui looks weird otherwise (0. workflow step)
    unique(workflow_id, index),

    name text not null,

    prevent_document_edit boolean not null default false,
    prevent_invoice_pay   boolean not null default false,

    review_details_mandatory         boolean not null default false,
    general_ledger_account_mandatory boolean not null default false,
    cost_center_mandatory            boolean not null default false,
    cost_unit_mandatory              boolean not null default false,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select, insert, update, delete on table public.document_workflow_step to domonda_user;
grant select on public.document_workflow_step to domonda_wg_user;

create index document_workflow_step_workflow_id_idx on public.document_workflow_step (workflow_id);
create index document_workflow_step_index_idx on public.document_workflow_step (index);
create index document_workflow_step_name_idx on public.document_workflow_step (name);
create index document_workflow_step_prevent_document_edit_idx on public.document_workflow_step (prevent_document_edit);
create index document_workflow_step_prevent_invoice_pay_idx on public.document_workflow_step (prevent_invoice_pay);

----

create function public.document_workflow_step_previous_step(
    document_workflow_step public.document_workflow_step
) returns public.document_workflow_step as
$$
    select dws.* from document_workflow_step as dws
        left join document_workflow_step as curr_dws on (curr_dws.id = document_workflow_step_previous_step.document_workflow_step.id)
    where (
        dws.workflow_id = curr_dws.workflow_id
    ) and (
        dws.id <> curr_dws.id
    ) and (
        dws.index < curr_dws.index
    )
    order by dws.index desc
    limit 1
$$
language sql stable;

comment on function public.document_workflow_step_previous_step is 'Returns the previous workflow step following the index';

----

create function public.document_workflow_step_next_step(
    document_workflow_step public.document_workflow_step
) returns public.document_workflow_step as
$$
    select dws.* from document_workflow_step as dws
        left join document_workflow_step as curr_dws on (curr_dws.id = document_workflow_step_next_step.document_workflow_step.id)
    where (
        dws.workflow_id = curr_dws.workflow_id
    ) and (
        dws.id <> curr_dws.id
    ) and (
        dws.index > curr_dws.index
    )
    order by dws.index
    limit 1
$$
language sql stable;

comment on function public.document_workflow_step_next_step is 'Returns the next workflow step following the index';

----

create function public.document_workflow_sorted_document_workflow_steps(
    document_workflow public.document_workflow
) returns setof public.document_workflow_step as
$$
    select * from public.document_workflow_step
    where (workflow_id = document_workflow_sorted_document_workflow_steps.document_workflow.id)
    order by index
$$
language sql stable;

comment on function public.document_workflow_sorted_document_workflow_steps is 'Retrives the `DocumentWorkflowSteps` of the provided `DocumentWorkflow` sorted by their index.';

----

create function public.client_company_sorted_document_workflows(
    client_company public.client_company
) returns setof public.document_workflow as
$$
    select * from public.document_workflow
    where (client_company_id = client_company_sorted_document_workflows.client_company.company_id)
    order by name
$$
language sql stable;

comment on function public.client_company_sorted_document_workflows is 'Retrives the `DocumentWorkflows` of the provided `ClientCompany` sorted by their name.';

----

create function public.document_workflow_step_full_name(
    document_workflow_step public.document_workflow_step
) returns text as
$$
    select document_workflow_step.index || '. ' || document_workflow_step.name || ' (' || document_workflow.name || ')'
    from public.document_workflow
    where document_workflow.id = document_workflow_step.workflow_id
$$
language sql stable;

comment on function public.document_workflow_step_full_name is E'@notNull\nDerives the full name of the step. Full name format is as follows: "`DocumentWorkflowStep.index`. `DocumentWorkflowStep.name` (`DocumentWorkflow.name`)".';

----

create function public.document_workflow_step_index_with_name(
    document_workflow_step public.document_workflow_step
) returns text as
$$
    select document_workflow_step.index || '. ' || document_workflow_step.name
$$
language sql immutable strict;

comment on function public.document_workflow_step_index_with_name is E'@notNull\nDerives the index + name of the step.';

----

create function public.create_document_workflow_step(
    workflow_id                      uuid,
    index                            int,
    name                             text,
    prevent_document_edit            boolean = false,
    prevent_invoice_pay              boolean = false,
    review_details_mandatory         boolean = false,
    general_ledger_account_mandatory boolean = false,
    cost_center_mandatory            boolean = false,
    cost_unit_mandatory              boolean = false
) returns public.document_workflow_step as
$$
    insert into public.document_workflow_step (id, workflow_id, index, name, prevent_document_edit, prevent_invoice_pay, review_details_mandatory, general_ledger_account_mandatory, cost_center_mandatory, cost_unit_mandatory)
        values (
            uuid_generate_v4(),
            create_document_workflow_step.workflow_id,
            create_document_workflow_step.index,
            create_document_workflow_step.name,
            create_document_workflow_step.prevent_document_edit,
            create_document_workflow_step.prevent_invoice_pay,
            create_document_workflow_step.review_details_mandatory,
            create_document_workflow_step.general_ledger_account_mandatory,
            create_document_workflow_step.cost_center_mandatory,
            create_document_workflow_step.cost_unit_mandatory
        )
    returning *
$$
language sql volatile strict;

----

create function public.update_document_workflow_step(
    id                               uuid,
    index                            int,
    name                             text,
    prevent_document_edit            boolean = false,
    prevent_invoice_pay              boolean = false,
    review_details_mandatory         boolean = false,
    general_ledger_account_mandatory boolean = false,
    cost_center_mandatory            boolean = false,
    cost_unit_mandatory              boolean = false
) returns public.document_workflow_step as
$$
    update public.document_workflow_step
    set
        index=update_document_workflow_step.index,
        name=update_document_workflow_step.name,
        prevent_document_edit=update_document_workflow_step.prevent_document_edit,
        prevent_invoice_pay=update_document_workflow_step.prevent_invoice_pay,
        review_details_mandatory=update_document_workflow_step.review_details_mandatory,
        general_ledger_account_mandatory=update_document_workflow_step.general_ledger_account_mandatory,
        cost_center_mandatory=update_document_workflow_step.cost_center_mandatory,
        cost_unit_mandatory=update_document_workflow_step.cost_unit_mandatory,
        updated_at=now()
    where id = update_document_workflow_step.id
    returning *
$$
language sql volatile strict;

----

create function public.delete_document_workflow_step(
    id uuid
) returns public.document_workflow_step as
$$
    delete from public.document_workflow_step
    where id = delete_document_workflow_step.id
    returning *
$$
language sql volatile strict;

----

create function public.move_document_workflow_step(
    id    uuid,
    index int
) returns public.document_workflow_step as
$$
declare
    moving_document_workflow_step record;
begin
    select
        * into moving_document_workflow_step
    from public.document_workflow_step
    where document_workflow_step.id = move_document_workflow_step.id;

    -- handle case when there is already a step on the given location
    if exists (
        select 1 from public.document_workflow_step where (
            document_workflow_step.workflow_id = moving_document_workflow_step.workflow_id
        ) and (
            document_workflow_step.index = move_document_workflow_step.index
        )
    ) then

        -- set moving step index to max int to avoid unique collision
        update public.document_workflow_step
        set
            index=2147483647 -- max_int
        where document_workflow_step.id = moving_document_workflow_step.id;

        -- update colliding step
        update public.document_workflow_step
        set
            index=moving_document_workflow_step.index,
            updated_at=now()
        where (
            document_workflow_step.workflow_id = moving_document_workflow_step.workflow_id
        ) and (
            document_workflow_step.index = move_document_workflow_step.index
        );

        -- update and return moving step
        update public.document_workflow_step
        set
            index=move_document_workflow_step.index,
            updated_at=now()
        where document_workflow_step.id = moving_document_workflow_step.id
        returning
            * into moving_document_workflow_step;

        return moving_document_workflow_step;

    end if;

    -- index position is free
    update public.document_workflow_step
    set
        index=move_document_workflow_step.index,
        updated_at=now()
    where document_workflow_step.id = move_document_workflow_step.id
    returning
        * into moving_document_workflow_step;

    return moving_document_workflow_step;
end
$$
language plpgsql volatile strict;

----

create function public.document_workflow_steps_by_ids(
    ids uuid[]
) returns setof public.document_workflow_step as
$$
    select *
    from public.document_workflow_step
    where id = any(document_workflow_steps_by_ids.ids)
$$
language sql stable;

comment on function public.document_workflow_steps_by_ids is '@name documentWorkflowStepsByRowIds';

----

create function public.document_workflow_first_step(
    document_workflow public.document_workflow
) returns public.document_workflow_step as
$$
    select *
    from public.document_workflow_step
    where workflow_id = document_workflow.id
    order by index asc
    limit 1
$$
language sql stable;

----

create function public.document_workflow_step_is_first_step(
    document_workflow_step public.document_workflow_step
) returns boolean as
$$
    select
        document_workflow_step = public.document_workflow_first_step(document_workflow)
    from public.document_workflow
    where document_workflow.id = document_workflow_step.workflow_id
$$
language sql stable;

comment on function public.document_workflow_step_is_first_step is '@notNull';

----

create function public.document_workflow_last_step(
    document_workflow public.document_workflow
) returns public.document_workflow_step as
$$
    select *
    from public.document_workflow_step
    where workflow_id = document_workflow.id
    order by index desc
    limit 1
$$
language sql stable;

----

create function public.document_workflow_step_is_last_step(
    document_workflow_step public.document_workflow_step
) returns boolean as
$$
    select
        document_workflow_step = public.document_workflow_last_step(document_workflow)
    from public.document_workflow
    where document_workflow.id = document_workflow_step.workflow_id
$$
language sql stable;

comment on function public.document_workflow_step_is_last_step is '@notNull';
