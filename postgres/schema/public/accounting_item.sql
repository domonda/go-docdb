create view public.accounting_item as
(
  select
    invoice_accounting_item.id,
    invoice.partner_company_id,
    invoice_accounting_item.general_ledger_account_id,
    invoice_accounting_item.title,
    document_category.document_type,
    invoice_accounting_item.booking_type,
    invoice_accounting_item.value_added_tax_id,
    invoice_accounting_item.value_added_tax_percentage_id,
    invoice_accounting_item.updated_at,
    invoice_accounting_item.created_at
  from public.invoice_accounting_item
    inner join public.invoice on invoice.document_id = invoice_accounting_item.invoice_document_id
    inner join public.document on document.id = invoice.document_id
    inner join public.document_category on document.category_id = document_category.id
) union all (
  select
    journal_accounting_item.id,
    partner_account.partner_company_id,
    journal_accounting_item.general_ledger_account_id,
    journal_accounting_item.title,
    -- TODO: this is not always the case, but we don't have a document type in the journal accounting item
    (case partner_account."type"
      when 'VENDOR' then 'INCOMING_INVOICE'
      else 'OUTGOING_INVOICE'
    end)::public.document_type as document_type,
    (case partner_account."type"
      when 'VENDOR' then 'DEBIT'
      else 'CREDIT'
    end)::public.invoice_accounting_item_booking_type as booking_type,
    journal_accounting_item.value_added_tax_id,
    journal_accounting_item.value_added_tax_percentage_id,
    journal_accounting_item.updated_at,
    journal_accounting_item.created_at
  from public.journal_accounting_item
    inner join public.partner_account on partner_account.id = journal_accounting_item.partner_account_id
);

grant select on public.accounting_item to domonda_user;

comment on column public.accounting_item.partner_company_id is '@notNull';
comment on column public.accounting_item.general_ledger_account_id is '@notNull';
comment on column public.accounting_item.title is '@notNull';
comment on column public.accounting_item.document_type is '@notNull';
comment on column public.accounting_item.booking_type is '@notNull';
comment on column public.accounting_item.updated_at is '@notNull';
comment on column public.accounting_item.created_at is '@notNull';
comment on view public.accounting_item is $$
@primaryKey id
@foreignKey (partner_company_id) references public.partner_company(id)
@foreignKey (general_ledger_account_id) references public.general_ledger_account(id)
@foreignKey (value_added_tax_id) references public.value_added_tax(id)
@foreignKey (value_added_tax_percentage_id) references public.value_added_tax_percentage(id)
An `AccountingItem` which is a union of domonda''s `InvoiceAccountingItem` and the `JournalAccountingItem`. Mainly useful for statistics and the accounting suggestion system.$$;
