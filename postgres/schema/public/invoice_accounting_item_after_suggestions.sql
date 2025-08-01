create function public.create_invoice_accounting_item(
    invoice_document_id           uuid,
    title                         text,
    booking_type                  public.invoice_accounting_item_booking_type,
    amount_type                   public.invoice_accounting_item_amount_type,
    amount                        float8,
    general_ledger_account_id     uuid,
    value_added_tax_id            uuid = null,
    value_added_tax_percentage_id uuid = null
) returns public.invoice_accounting_item as $$
declare
  created_invoice_accounting_item     public.invoice_accounting_item;
  cent_offset_invoice_accounting_item public.invoice_accounting_item;
begin
    insert into public.invoice_accounting_item (
        invoice_document_id,
        title,
        booking_type,
        amount_type,
        amount,
        general_ledger_account_id,
        value_added_tax_id,
        value_added_tax_percentage_id,
        created_by
    ) values (
        create_invoice_accounting_item.invoice_document_id,
        create_invoice_accounting_item.title,
        create_invoice_accounting_item.booking_type,
        create_invoice_accounting_item.amount_type,
        create_invoice_accounting_item.amount,
        create_invoice_accounting_item.general_ledger_account_id,
        create_invoice_accounting_item.value_added_tax_id,
        create_invoice_accounting_item.value_added_tax_percentage_id,
        private.current_user_id()
    )
    returning * into created_invoice_accounting_item;

    -- check and adjust cent difference, if necessary
    perform private.adjust_cent_diff_in_invoice_accounting_items_on_invoice(create_invoice_accounting_item.invoice_document_id);

    -- if the remaining amount is zero, update the invoice's net
    if (select public.invoice_accounting_items_remaining_amount_is_zero(invoice)
    from public.invoice
    where invoice.document_id = created_invoice_accounting_item.invoice_document_id)
    then
      update public.invoice set
        net=(select abs(private.signed_invoice_accounting_items_net_sum(array_agg(invoice_accounting_item)))
          from public.invoice_accounting_item
          where invoice_accounting_item.invoice_document_id = invoice.document_id),
        net_confirmed_by=private.current_user_id(),
        net_confirmed_at=now(),
        updated_at=now()
      where invoice.document_id = created_invoice_accounting_item.invoice_document_id;
    end if;

    return created_invoice_accounting_item;
end
$$
language plpgsql volatile;

----

create function public.update_invoice_accounting_item(
    id                            uuid,
    invoice_document_id           uuid,
    title                         text,
    booking_type                  public.invoice_accounting_item_booking_type,
    amount_type                   public.invoice_accounting_item_amount_type,
    amount                        float8,
    general_ledger_account_id     uuid,
    value_added_tax_id            uuid = null,
    value_added_tax_percentage_id uuid = null
) returns public.invoice_accounting_item as $$
declare
  updated_invoice_accounting_item     public.invoice_accounting_item;
  cent_offset_invoice_accounting_item public.invoice_accounting_item;
begin
    update public.invoice_accounting_item
        set
          invoice_document_id=update_invoice_accounting_item.invoice_document_id,
          title=update_invoice_accounting_item.title,
          booking_type=update_invoice_accounting_item.booking_type,
          amount_type=update_invoice_accounting_item.amount_type,
          amount=update_invoice_accounting_item.amount,
          general_ledger_account_id=update_invoice_accounting_item.general_ledger_account_id,
          value_added_tax_id=update_invoice_accounting_item.value_added_tax_id,
          value_added_tax_percentage_id=update_invoice_accounting_item.value_added_tax_percentage_id,
          updated_by=private.current_user_id(),
          updated_at=now()
    where invoice_accounting_item.id = update_invoice_accounting_item.id
    returning * into updated_invoice_accounting_item;

    -- check and adjust cent difference, if necessary
    perform private.adjust_cent_diff_in_invoice_accounting_items_on_invoice(update_invoice_accounting_item.invoice_document_id);

    -- if the remaining amount is zero, update the invoice's net
    if (select public.invoice_accounting_items_remaining_amount_is_zero(invoice)
    from public.invoice
    where invoice.document_id = updated_invoice_accounting_item.invoice_document_id)
    then
      update public.invoice set
        net=(select abs(private.signed_invoice_accounting_items_net_sum(array_agg(invoice_accounting_item)))
          from public.invoice_accounting_item
          where invoice_accounting_item.invoice_document_id = invoice.document_id),
        net_confirmed_by=private.current_user_id(),
        net_confirmed_at=now(),
        updated_at=now()
      where invoice.document_id = updated_invoice_accounting_item.invoice_document_id;
    end if;

    return updated_invoice_accounting_item;
end
$$
language plpgsql volatile;
