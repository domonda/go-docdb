create type public.partner_company_invoices_statistics_result as (
  client_invoices_sum           float8,
  client_invoices_count         int,
  client_invoices_ids           uuid[],
  vendor_invoices_sum           float8,
  vendor_invoices_count         int,
  vendor_invoices_ids           uuid[],
  has_foreign_currency_invoices boolean
);

comment on column public.partner_company_invoices_statistics_result.client_invoices_sum is '@notNull';
comment on column public.partner_company_invoices_statistics_result.client_invoices_count is '@notNull';
comment on column public.partner_company_invoices_statistics_result.client_invoices_ids is '@notNull';
comment on column public.partner_company_invoices_statistics_result.vendor_invoices_sum is '@notNull';
comment on column public.partner_company_invoices_statistics_result.vendor_invoices_count is '@notNull';
comment on column public.partner_company_invoices_statistics_result.vendor_invoices_ids is '@notNull';
comment on column public.partner_company_invoices_statistics_result.has_foreign_currency_invoices is '@notNull';

create function public.partner_company_invoices_statistics(
  partner_company public.partner_company
) returns public.partner_company_invoices_statistics_result as $$
  select
    coalesce(
      sum(coalesce(public.invoice_converted_signed_discounted_total(invoice), 0))
      filter (where document_category.document_type = 'OUTGOING_INVOICE' and public.document_payment_status(document) is distinct from 'NOT_PAYABLE'),
      0
    )                                                                                         as client_invoices_sum,
    coalesce(count(*) filter (where document_category.document_type = 'OUTGOING_INVOICE'), 0) as client_invoices_count,
    coalesce(
      array_agg(invoice.document_id) filter (where document_category.document_type = 'OUTGOING_INVOICE'),
      '{}'
    )                                                                                         as client_invoices_ids,
    coalesce(
      sum(coalesce(public.invoice_converted_signed_discounted_total(invoice), 0))
      filter (where document_category.document_type = 'INCOMING_INVOICE' and public.document_payment_status(document) is distinct from 'NOT_PAYABLE'),
      0
    )                                                                                         as vendor_invoices_sum,
    coalesce(count(*) filter (where document_category.document_type = 'INCOMING_INVOICE'), 0) as vendor_invoices_count,
    coalesce(
      array_agg(invoice.document_id) filter (where document_category.document_type = 'INCOMING_INVOICE'),
      '{}'
    )                                                                                         as vendor_invoices_ids,
    coalesce((count(1) filter (where invoice.currency is distinct from 'EUR')) > 0, false)    as has_foreign_currency_invoices
  from public.invoice
    inner join (
      public.document
        inner join public.document_category on document_category.id = document.category_id
    ) on document.id = invoice.document_id
  where invoice.partner_company_id = partner_company.id
  and not document.superseded
  and not document.archived
$$ language sql stable strict;
comment on function public.partner_company_invoices_statistics is '@notNull';

----

create type public.partner_company_payments_statistics_result as (
  client_transaction_payments_sum   float8,
  client_transaction_payments_count int,
  client_transaction_payments_ids   uuid[],
  vendor_transaction_payments_sum   float8,
  vendor_transaction_payments_count int,
  vendor_transaction_payments_ids   uuid[],
  client_manual_payments_sum        float8,
  client_manual_payments_count      int,
  client_manual_payments_ids        uuid[],
  vendor_manual_payments_sum        float8,
  vendor_manual_payments_count      int,
  vendor_manual_payments_ids        uuid[]
);

comment on column public.partner_company_payments_statistics_result.client_transaction_payments_sum is '@notNull';
comment on column public.partner_company_payments_statistics_result.client_transaction_payments_count is '@notNull';
comment on column public.partner_company_payments_statistics_result.client_transaction_payments_ids is '@notNull';
comment on column public.partner_company_payments_statistics_result.vendor_transaction_payments_sum is '@notNull';
comment on column public.partner_company_payments_statistics_result.vendor_transaction_payments_count is '@notNull';
comment on column public.partner_company_payments_statistics_result.vendor_transaction_payments_ids is '@notNull';
comment on column public.partner_company_payments_statistics_result.client_manual_payments_sum is '@notNull';
comment on column public.partner_company_payments_statistics_result.client_manual_payments_count is '@notNull';
comment on column public.partner_company_payments_statistics_result.client_manual_payments_ids is '@notNull';
comment on column public.partner_company_payments_statistics_result.vendor_manual_payments_sum is '@notNull';
comment on column public.partner_company_payments_statistics_result.vendor_manual_payments_count is '@notNull';
comment on column public.partner_company_payments_statistics_result.vendor_manual_payments_ids is '@notNull';

create function public.partner_company_payments_statistics(
  partner_company public.partner_company
) returns public.partner_company_payments_statistics_result as $$
  with payment as (
    (
      -- all transactions that are linked to documents of the same partner company
      select
        distinct on (money_transaction.id)
        money_transaction.id as transaction_payment_id,
        (case
          when document_category.document_type = 'OUTGOING_INVOICE' then 'CLIENT'
          when document_category.document_type = 'INCOMING_INVOICE' then 'VENDOR'
          else null
        end)::text as transaction_payment_type,
        public.money_transaction_signed_amount(money_transaction) * -1 as transaction_payment_amount,
        null::uuid as manual_payment_id,
        null::text as manual_payment_type,
        null::float8 as manual_payment_amount
      from public.invoice
        inner join (
          public.document
            inner join public.document_category on document_category.id = document.category_id
        ) on document.id = invoice.document_id
        inner join (
          public.document_money_transaction
            inner join public.money_transaction on money_transaction.id = document_money_transaction.money_transaction_id
        ) on document_money_transaction.document_id = document.id
      where invoice.partner_company_id = partner_company.id
      and not document.superseded
      and not document.archived
      -- this transaction is not linked to multiple documents with a different partner companies
      and not exists (
        (
          select from public.document_bank_transaction as out_document_bank_transaction
            inner join public.invoice as out_invoice on out_invoice.document_id = out_document_bank_transaction.document_id
          where out_document_bank_transaction.bank_transaction_id = money_transaction.id
          and out_document_bank_transaction.document_id <> document.id
          and out_invoice.partner_company_id <> partner_company.id
        ) union (
          select from public.document_credit_card_transaction as out_document_credit_card_transaction
            inner join public.invoice as out_invoice on out_invoice.document_id = out_document_credit_card_transaction.document_id
          where out_document_credit_card_transaction.credit_card_transaction_id = money_transaction.id
          and out_document_credit_card_transaction.document_id <> document.id
          and out_invoice.partner_company_id <> partner_company.id
        ) union (
          select from public.document_cash_transaction as out_document_cash_transaction
            inner join public.invoice as out_invoice on out_invoice.document_id = out_document_cash_transaction.document_id
          where out_document_cash_transaction.cash_transaction_id = money_transaction.id
          and out_document_cash_transaction.document_id <> document.id
          and out_invoice.partner_company_id <> partner_company.id
        )
      )
    ) union all (
      -- all invoices that have transaction linked to multiple documents with a different partner companies
      select
        money_transaction.id as transaction_payment_id,
        (case
          when document_category.document_type = 'OUTGOING_INVOICE' then 'CLIENT'
          when document_category.document_type = 'INCOMING_INVOICE' then 'VENDOR'
          else null
        end)::text as transaction_payment_type,
        public.invoice_converted_signed_discounted_total(invoice) * -1 as transaction_payment_amount,
        null::uuid as manual_payment_id,
        null::text as manual_payment_type,
        null::float8 as manual_payment_amount
      from public.invoice
        inner join (
          public.document
            inner join public.document_category on document_category.id = document.category_id
        ) on document.id = invoice.document_id
        inner join (
          public.document_money_transaction
            inner join public.money_transaction on money_transaction.id = document_money_transaction.money_transaction_id
        ) on document_money_transaction.document_id = document.id
      where invoice.partner_company_id = partner_company.id
      and not document.superseded
      and not document.archived
      -- this transaction is linked to multiple documents with a different partner companies
      and exists (
        (
          select from public.document_bank_transaction as out_document_bank_transaction
            inner join public.invoice as out_invoice on out_invoice.document_id = out_document_bank_transaction.document_id
          where out_document_bank_transaction.bank_transaction_id = money_transaction.id
          and out_document_bank_transaction.document_id <> document.id
          and out_invoice.partner_company_id <> partner_company.id
        ) union (
          select from public.document_credit_card_transaction as out_document_credit_card_transaction
            inner join public.invoice as out_invoice on out_invoice.document_id = out_document_credit_card_transaction.document_id
          where out_document_credit_card_transaction.credit_card_transaction_id = money_transaction.id
          and out_document_credit_card_transaction.document_id <> document.id
          and out_invoice.partner_company_id <> partner_company.id
        ) union (
          select from public.document_cash_transaction as out_document_cash_transaction
            inner join public.invoice as out_invoice on out_invoice.document_id = out_document_cash_transaction.document_id
          where out_document_cash_transaction.cash_transaction_id = money_transaction.id
          and out_document_cash_transaction.document_id <> document.id
          and out_invoice.partner_company_id <> partner_company.id
        )
      )
    ) union all (
      -- all invoices that are manually paid
      select
        null::uuid as transaction_payment_id,
        null::text as transaction_payment_type,
        null::float8 as transaction_payment_amount,
        invoice.document_id as manual_payment_id,
        (case
          when document_category.document_type = 'OUTGOING_INVOICE' then 'CLIENT'
          when document_category.document_type = 'INCOMING_INVOICE' then 'VENDOR'
          else null
        end)::text as manual_payment_type,
        public.invoice_converted_discounted_total(invoice) * -1 as manual_payment_amount
      from public.invoice
        inner join (
          public.document
            inner join public.document_category on document_category.id = document.category_id
        ) on document.id = invoice.document_id
      where invoice.partner_company_id = partner_company.id
      and not document.superseded
      and not document.archived
      and public.document_payment_status(document) is distinct from 'NOT_PAYABLE'
      and public.document_payment_status(document) is distinct from 'NOT_PAID'
      and not exists (
        (
          select from public.document_bank_transaction where document_bank_transaction.document_id = document.id limit 1
        ) union (
          select from public.document_credit_card_transaction where document_credit_card_transaction.document_id = document.id limit 1
        ) union (
          select from public.document_cash_transaction where document_cash_transaction.document_id = document.id limit 1
        )
      )
    )
  )
  select
    coalesce(sum(payment.transaction_payment_amount) filter (where payment.transaction_payment_type = 'CLIENT'), 0)      as client_transaction_payments_sum,
    coalesce(count(*) filter (where payment.transaction_payment_type = 'CLIENT'), 0)                                     as client_transaction_payments_count,
    coalesce(array_agg(payment.transaction_payment_id) filter (where payment.transaction_payment_type = 'CLIENT'), '{}') as client_transaction_payments_ids,
    coalesce(sum(payment.transaction_payment_amount) filter (where payment.transaction_payment_type = 'VENDOR'), 0)      as vendor_transaction_payments_sum,
    coalesce(count(*) filter (where payment.transaction_payment_type = 'VENDOR'), 0)                                     as vendor_transaction_payments_count,
    coalesce(array_agg(payment.transaction_payment_id) filter (where payment.transaction_payment_type = 'VENDOR'), '{}') as vendor_transaction_payments_ids,
    coalesce(sum(payment.manual_payment_amount) filter (where payment.manual_payment_type = 'CLIENT'), 0)                as client_manual_payments_sum,
    coalesce(count(*) filter (where payment.manual_payment_type = 'CLIENT'), 0)                                          as client_manual_payments_count,
    coalesce(array_agg(payment.manual_payment_id) filter (where payment.manual_payment_type = 'CLIENT'), '{}')           as client_manual_payments_ids,
    coalesce(sum(payment.manual_payment_amount) filter (where payment.manual_payment_type = 'VENDOR'), 0)                as vendor_manual_payments_sum,
    coalesce(count(*) filter (where payment.manual_payment_type = 'VENDOR'), 0)                                          as vendor_manual_payments_count,
    coalesce(array_agg(payment.manual_payment_id) filter (where payment.manual_payment_type = 'VENDOR'), '{}')           as vendor_manual_payments_ids
  from payment
$$ language sql stable strict;
comment on function public.partner_company_payments_statistics is '@notNull';
