-- sometimes you can pay an "other document". for example
-- you get a payment description for which you get an
-- invoice AFTER you pay it. this is why the paid status
-- does not connect to an invoice
-- when adding more statuses, make sure to update `rule.document_condition_payment_status` and `public.filter_documents_paid_status`
create type public.document_payment_status as enum (
  'NOT_PAYABLE', -- if the document cannot be paid at all
  'NOT_PAID',
  'PARTIALLY_PAID', --see TODO below
  'PAID_WITH_BANK',
  'PAID_WITH_CREDITCARD',
  'PAID_WITH_CASH',
  'PAID_WITH_PAYPAL',
  'PAID_WITH_STRIPE',
  'PAID_WITH_TRANSFERWISE',
  'PAID_WITH_DIRECT_DEBIT',
  'EXPENSES_PAID'
);

create function public.document_payment_status(
  document public.document
) returns public.document_payment_status as $$
  select (case
    -- TODO: necessary? we might want to have a state like "partially paid with bank", this can be currently
    -- depicted as: public.document_payment_status(document) = 'PAID_WITH_BANK' AND invoice.partially_paid
    when (select partially_paid from public.invoice where invoice.document_id = document.id) then 'PARTIALLY_PAID'
    -- paid through XS2A
    when exists(select from public.bank_payment where bank_payment.status = 'FINISHED' and bank_payment.document_id = document.id) then 'PAID_WITH_BANK'
    -- has a matched bank transaction
    when exists(select from public.document_bank_transaction where document_bank_transaction.document_id = document.id) then 'PAID_WITH_BANK'
    -- has a matched credit-card transaction
    when exists(select from public.document_credit_card_transaction where document_credit_card_transaction.document_id = document.id) then 'PAID_WITH_CREDITCARD'
    -- has a matched cash transaction
    when exists(select from public.document_cash_transaction where document_cash_transaction.document_id = document.id) then 'PAID_WITH_CASH'
    -- is of cash book booking type
    when exists(select from public.document_category where document_category.id = document.category_id and booking_type = 'CASH_BOOK') then 'PAID_WITH_CASH'
    -- TODO-db-200615 check other document<->transaction matches
    when exists (
      -- this is a credit-note with an invoice whose total is equal or smaller
      select from public.invoice
      where invoice.document_id = document.id
      and invoice.credit_memo
      and invoice.credit_memo_for_invoice_document_id is not null
      and exists (select from public.invoice as invoice_in
        where invoice_in.document_id = invoice.credit_memo_for_invoice_document_id
        and invoice_in.total <= invoice.total)
    ) then 'NOT_PAYABLE'
    when exists (
      -- this is an invoice with a credit-note whose total is equal or greater
      select from public.invoice
      where invoice.document_id = document.id
      and not invoice.credit_memo
      and exists (select from public.invoice as invoice_in
        where invoice_in.credit_memo
        and invoice_in.credit_memo_for_invoice_document_id is not null
        and invoice_in.credit_memo_for_invoice_document_id = invoice.document_id
        and invoice_in.total >= invoice.total)
    ) then 'NOT_PAYABLE'
    -- invoice partner is always paid with direct debit
    when exists (
      select from public.invoice
        inner join public.partner_company on partner_company.id = invoice.partner_company_id
      where invoice.document_id = document.id
      and partner_company.paid_with_direct_debit
    ) then 'PAID_WITH_DIRECT_DEBIT'
    else coalesce((select case invoice.payment_status
        -- map invoice to document payment_status
        when 'NOT_PAYABLE' then 'NOT_PAYABLE'
        when 'CREDITCARD' then 'PAID_WITH_CREDITCARD'
        when 'CASH' then 'PAID_WITH_CASH'
        when 'EXPENSES_PAID' then 'EXPENSES_PAID'
        when 'BANK' then 'PAID_WITH_BANK'
        when 'PAYPAL' then 'PAID_WITH_PAYPAL'
        when 'TRANSFERWISE' then 'PAID_WITH_TRANSFERWISE'
        when 'DIRECT_DEBIT' then 'PAID_WITH_DIRECT_DEBIT'
        else 'NOT_PAID'
      end
      from public.invoice
      where invoice.document_id = document.id),
      'NOT_PAYABLE' -- currently, only invoices can be paid (even though this is not necessarily true)
    )
  end)::public.document_payment_status
$$ language sql stable
security definer;

comment on function public.document_payment_status is '@notNull';

----

create function public.document_is_paid(
    document public.document
) returns boolean as
$$
  select
    coalesce(not invoice.partially_paid, true)
    and dps <> 'NOT_PAYABLE'
    and dps <> 'NOT_PAID'
  from public.document_payment_status(document) as dps
    left join public.invoice on invoice.document_id = document.id
$$
language sql stable;

comment on function public.document_is_paid is '@notNull';

----

create function public.invoice_is_paid(
  invoice public.invoice
) returns boolean as
$$
  select
    coalesce(not invoice.partially_paid, true)
    and dps <> 'NOT_PAYABLE'
    and dps <> 'NOT_PAID'
  from public.document, public.document_payment_status(document) as dps
  where document.id = invoice.document_id
$$
language sql stable;

comment on function public.invoice_is_paid is '@notNull';

----

create function public.invoice_can_update_partially_paid(
  invoice public.invoice
) returns boolean as
$$
  select (booking_type is null
      or booking_type <> 'CASH_BOOK')
    and (document_type = 'INCOMING_INVOICE'
      or document_type = 'OUTGOING_INVOICE')
  from public.document
    inner join public.document_category on document_category.id = document.category_id
  where document.id = invoice.document_id
$$
language sql stable strict;

comment on function public.invoice_can_update_partially_paid is E'@notNull\nIs the `Invoice` eligible for a `partiallyPaid` update.';

----

create function public.invoice_can_update_payment_status(
  invoice public.invoice
) returns boolean as
$$
  select bank_payment is null
    and (booking_type is null
      or booking_type <> 'CASH_BOOK')
    and (document_type = 'INCOMING_INVOICE'
      or document_type = 'OUTGOING_INVOICE')
    and (not coalesce(partner_company.paid_with_direct_debit, false))
  from public.document
    inner join public.document_category on document_category.id = document.category_id
    left join public.bank_payment on bank_payment.document_id = invoice.document_id and status = 'FINISHED'
    left join public.partner_company on partner_company.id = invoice.partner_company_id
  where document.id = invoice.document_id
$$
language sql stable strict;

comment on function public.invoice_can_update_payment_status is E'@notNull\nIs the `Invoice` eligible for a `paymentStatus` update.';

----

create function public.invoice_can_update_paid_date(
  invoice public.invoice
) returns boolean as
$$
  -- TODO: include partial payment?
  select ((invoice.paid_date is not null) and (invoice.payment_status is null)
      or ((invoice.payment_status is not null) and (invoice.payment_status <> 'NOT_PAYABLE')))
    and not exists (select from public.document_money_transaction where document_id = invoice.document_id)
    and not exists (select from public.bank_payment where document_id = invoice.document_id and status = 'FINISHED')
$$
language sql stable strict;

comment on function public.invoice_can_update_paid_date is E'@notNull\nIs the `Invoice` eligible for a `paidDate` update.';

----

create function public.invoice_can_pay(
  invoice public.invoice
) returns boolean as
$$
  select
    not exists (
      select from public.document_workflow_step
      where document_workflow_step.id = document.workflow_step_id
      and document_workflow_step.prevent_invoice_pay
      and not private.current_user_super()
      and not exists (
        select from control.client_company_user
        where client_company_user.client_company_id = document.client_company_id
        and client_company_user.user_id = (select private.current_user_id())
        and role_name in ('ADMIN')
      )
    )
    and (
      invoice.partially_paid
      or (
        public.document_payment_status(document) = 'NOT_PAID'
        and (booking_type is null or ignore_booking_type_paid_assumption)
        and (document_type = 'INCOMING_INVOICE' or document_type = 'OUTGOING_INVOICE')
        and ((document_type = 'INCOMING_INVOICE' and (not invoice.credit_memo))
          or (document_type = 'OUTGOING_INVOICE' and invoice.credit_memo))
      )
    )
  from public.document
    inner join public.document_category on document_category.id = document.category_id
  where document.id = invoice.document_id
$$
language sql stable strict
security definer; -- because the user might not have access to the workflow_step and therefore cannot read the prevent fields

comment on function public.invoice_can_pay is E'@notNull\nIs the `Invoice` eligible for being paid.';

----

create function public.invoice_can_pain001(
  invoice public.invoice
) returns boolean as
$$
  select
    not exists (
      select from public.document_workflow_step
      where document_workflow_step.id = document.workflow_step_id
      and document_workflow_step.prevent_invoice_pay
      and not private.current_user_super()
      and not exists (
        select from control.client_company_user
        where client_company_user.client_company_id = document.client_company_id
        and client_company_user.user_id = (select private.current_user_id())
        and role_name in ('ADMIN')
      )
    )
  from public.document
    inner join public.document_category on document_category.id = document.category_id
  where document.id = invoice.document_id
$$
language sql stable strict
security definer; -- because the user might not have access to the workflow_step and therefore cannot read the prevent fields

comment on function public.invoice_can_pain001 is E'@notNull\nIs the `Invoice` eligible for generating a pain.001 payment XML.';

create function public.invoice_can_pain008(
  invoice public.invoice
) returns boolean as
$$
  select
    document_category.document_type = 'OUTGOING_INVOICE'
    and not invoice.credit_memo
  from public.document
    inner join public.document_category on document_category.id = document.category_id
  where document.id = invoice.document_id
$$
language sql stable strict
security definer; -- because the user might not have access to the workflow_step and therefore cannot read the prevent fields

comment on function public.invoice_can_pain008 is E'@notNull\nIs the `Invoice` eligible for generating a pain.008 direct debit XML.';

----

create function public.invoice_is_discount_applicable(
  invoice public.invoice
) returns boolean as
$$
  select coalesce(invoice.discount_until > now(), false)
$$
language sql immutable strict;

comment on function public.invoice_is_discount_applicable is E'@notNull\nChecks if the `Invoice` discount is still applicable.';
