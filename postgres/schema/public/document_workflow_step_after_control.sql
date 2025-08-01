create function public.document_is_in_prevent_edit_workflow_step(
    document public.document
) returns boolean as $$
    select exists (
        select from public.document_workflow_step
        where document_workflow_step.id = document.workflow_step_id
        and document_workflow_step.prevent_document_edit
        and not private.current_user_super()
        and not exists (
            select from control.client_company_user
            where client_company_user.client_company_id = document.client_company_id
            and client_company_user.user_id = (select private.current_user_id())
            and role_name in ('ADMIN', 'VERIFIER')
        )
    )
$$ language sql stable strict;
comment on function public.document_is_in_prevent_edit_workflow_step is '@notNull';

----

create function public.document_is_next_workflow_step_prevented(
    document public.document
) returns boolean as $$
    select
        (
            document_workflow_step.review_details_mandatory
            and not exists (
                select from public.invoice
                where invoice.document_id = document.id
                and not (
                    invoice.partner_company_id is null
                    or invoice.invoice_number is null
                    or invoice.invoice_date is null
                    or invoice.total is null
                    or invoice.net is null
                )
            )
        ) or (
            document_workflow_step.general_ledger_account_mandatory
            and not exists (
                select from public.invoice_accounting_item
                where invoice_accounting_item.invoice_document_id = document.id
                and not (
                    invoice_accounting_item.general_ledger_account_id is null
                    or exists (
                        select from public.general_ledger_account
                        where general_ledger_account.id = invoice_accounting_item.general_ledger_account_id
                        -- general ledger accounts with a number '1' are dummy accounts
                        and general_ledger_account.number = '1'
                    )
                )
            )
        ) or (
            document_workflow_step.cost_center_mandatory
            and (
                not exists (
                    select from public.invoice_accounting_item
                    where invoice_accounting_item.invoice_document_id = document.id
                ) or exists (
                    select from public.invoice_accounting_item
                        left join public.invoice_accounting_item_cost_center on invoice_accounting_item_cost_center.invoice_accounting_item_id = invoice_accounting_item.id
                    where invoice_accounting_item.invoice_document_id = document.id
                    and invoice_accounting_item_cost_center is null
                )
            ) and not exists (
                select from public.invoice_cost_center
                where invoice_cost_center.document_id = document.id
            )
        ) or (
            document_workflow_step.cost_unit_mandatory
            and (
                not exists (
                    select from public.invoice_accounting_item
                    where invoice_accounting_item.invoice_document_id = document.id
                ) or exists (
                    select from public.invoice_accounting_item
                        left join public.invoice_accounting_item_cost_unit on invoice_accounting_item_cost_unit.invoice_accounting_item_id = invoice_accounting_item.id
                    where invoice_accounting_item.invoice_document_id = document.id
                    and invoice_accounting_item_cost_unit is null
                )
            ) and not exists (
                select from public.invoice_cost_unit
                where invoice_cost_unit.invoice_document_id = document.id
            )
        )
  from public.document_workflow_step
  where document_workflow_step.id = document.workflow_step_id
$$ language sql stable strict;

create function public.document_workflow_step_validate_change()
returns trigger as $$
begin
    if
        public.document_is_next_workflow_step_prevented(old)
        and (
            select (public.document_workflow_step_next_step(document_workflow_step)).id
            from public.document_workflow_step
            where document_workflow_step.id = old.workflow_step_id
        ) = new.workflow_step_id
    then
        if private.current_user_language() = 'de'
        then raise exception 'Um Freizugeben, müssen Sie folgende Daten zwingend angeben: Details der Prüfung, Sachkonto, Kostenstelle, Kostenträger';
        end if;

        raise exception 'In order to approve, you are required to provide the following mandatory data: Review details, Offset account / General ledger account, Cost center, Cost unit';
    end if;

    return new;
end
$$ language plpgsql stable;

create trigger document_workflow_step_validate_change
    before update on public.document
    for each row
    when (
        old.workflow_step_id is not null
        and new.workflow_step_id is not null
        and old.workflow_step_id is distinct from new.workflow_step_id
    )
    execute procedure public.document_workflow_step_validate_change();
