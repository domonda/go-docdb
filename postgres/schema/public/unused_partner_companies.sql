-- ignoring references from public.partner_account with referencing public.company_location
-- and ignoring references from public.partner_company_payment_preset
create function private.is_partner_company_used(partner_company_id uuid)
returns boolean as
$$
    select 
    exists(
        select from public.invoice
        where invoice.partner_company_id = is_partner_company_used.partner_company_id
    )
    or exists(
        select from public.other_document
        where other_document.partner_company_id = is_partner_company_used.partner_company_id
    )
    or exists(
        select from public.delivery_note
        where delivery_note.partner_company_id = is_partner_company_used.partner_company_id
    )
    or exists(
        select from public.document_field_value_partner_company
        where document_field_value_partner_company.value = is_partner_company_used.partner_company_id
    )
    or exists(
        select from public.bank_transaction
        where bank_transaction.partner_company_id = is_partner_company_used.partner_company_id
    )
    or exists(
        select from public.cash_transaction
        where cash_transaction.partner_company_id = is_partner_company_used.partner_company_id
    )
    or exists(
        select from public.paypal_transaction
        where paypal_transaction.partner_company_id = is_partner_company_used.partner_company_id
    )
    or exists(
        select from public.stripe_transaction
        where stripe_transaction.partner_company_id = is_partner_company_used.partner_company_id
    )
    or exists(
        select from public.credit_card_transaction
        where credit_card_transaction.partner_company_id = is_partner_company_used.partner_company_id
    )
    or exists(
        select from rule.invoice_partner_company_condition
        where invoice_partner_company_condition.partner_company_id = is_partner_company_used.partner_company_id
    )
    or exists(
        select from automation.workflow_trigger_filter_group_document_with_partner
        where workflow_trigger_filter_group_document_with_partner.partner_company_id = is_partner_company_used.partner_company_id
    )
$$
language sql stable strict;


create function public.partner_company_is_used(p public.partner_company)
returns boolean as
$$
    select private.is_partner_company_used(p.id)
$$
language sql stable strict;

comment on function public.partner_company_is_used is 'The `PartnerCompany` is referenced by documents, a partner account, money transactions, payment conditions or workflows.';

----

create function public.unused_partner_companies(
    client_company_id            uuid    = null,
    only_without_partner_account boolean = false
) returns setof public.partner_company as
$$
    select p.*
    from public.partner_company as p
    where (unused_partner_companies.client_company_id is null
            or p.client_company_id = unused_partner_companies.client_company_id
        )
        and not exists(
            select from public.invoice where partner_company_id = p.id
        )
        and not exists(
            select from public.other_document where partner_company_id = p.id
        )
        and not exists(
            select from public.delivery_note where partner_company_id = p.id
        )
        and not exists(
            select from public.document_field_value_partner_company where value = p.id
        )
        and not exists(
            select from public.bank_transaction where partner_company_id = p.id
        )
        and not exists(
            select from public.cash_transaction where partner_company_id = p.id
        )
        and not exists(
            select from public.paypal_transaction where partner_company_id = p.id
        )
        and not exists(
            select from public.stripe_transaction where partner_company_id = p.id
        )
        and not exists(
            select from public.credit_card_transaction where partner_company_id = p.id
        )
        and not exists(
            select from rule.invoice_partner_company_condition where partner_company_id = p.id
        )
        and not exists(
            select from automation.workflow_trigger_filter_group_document_with_partner where partner_company_id = p.id
        )
        -- and not exists(
        --     select from public.partner_company_payment_preset where partner_company_id = p.id
        -- )
        and (not unused_partner_companies.only_without_partner_account
            or not exists(
                select from public.partner_account where partner_company_id = p.id
            )
        )
$$
language sql stable;

comment on function public.unused_partner_companies is 'Returns `PartnerCompanies` that are not referenced by documents, payments, payment presets, or workflows. If true is passed for `onlyWithoutPartnerAccount` then only companies without a partner account (number) are returned.';

----

create type public.partner_company_usage as (
    num_partner_account bigint,
    num_invoice bigint,
    num_other_document bigint,
    num_delivery_note bigint,
    num_document_field_value_partner_company bigint,
    num_bank_transaction bigint,
    num_cash_transaction bigint,
    num_paypal_transaction bigint,
    num_stripe_transaction bigint,
    num_credit_card_transaction bigint,
    num_invoice_partner_company_condition bigint,
    num_workflow_trigger_filter_group_document_with_partner bigint,
    num_partner_company_payment_preset bigint
);

create function public.partner_company_usage(p public.partner_company)
returns public.partner_company_usage as
$$
    select
    (
        select count(*) from public.partner_account
        where partner_account.partner_company_id = p.id
    ) as num_partner_account,
    (
        select count(*) from public.invoice
        where invoice.partner_company_id = p.id
    ) as num_invoice,
    (
        select count(*) from public.other_document
        where other_document.partner_company_id = p.id
    ) as num_other_document,
    (
        select count(*) from public.delivery_note
        where delivery_note.partner_company_id = p.id
    ) as num_delivery_note,
    (
        select count(*) from public.document_field_value_partner_company
        where document_field_value_partner_company.value = p.id
    ) as num_document_field_value_partner_company,
    (
        select count(*) from public.bank_transaction
        where bank_transaction.partner_company_id = p.id
    ) as num_bank_transaction,
    (
        select count(*) from public.cash_transaction
        where cash_transaction.partner_company_id = p.id
    ) as num_cash_transaction,
    (
        select count(*) from public.paypal_transaction
        where paypal_transaction.partner_company_id = p.id
    ) as num_paypal_transaction,
    (
        select count(*) from public.stripe_transaction
        where stripe_transaction.partner_company_id = p.id
    ) as num_stripe_transaction,
    (
        select count(*) from public.credit_card_transaction
        where credit_card_transaction.partner_company_id = p.id
    ) as num_credit_card_transaction,
    (
        select count(*) from rule.invoice_partner_company_condition
        where invoice_partner_company_condition.partner_company_id = p.id
    ) as num_invoice_partner_company_condition,
    (
        select count(*) from automation.workflow_trigger_filter_group_document_with_partner
        where workflow_trigger_filter_group_document_with_partner.partner_company_id = p.id
    ) as num_workflow_trigger_filter_group_document_with_partner,
    (
        select count(*) from public.partner_company_payment_preset
        where partner_company_payment_preset.partner_company_id = p.id
    ) as num_partner_company_payment_preset
$$
language sql stable strict;
