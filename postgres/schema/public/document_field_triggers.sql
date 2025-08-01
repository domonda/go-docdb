create function public.sync_document_field_values()
returns trigger as $$
declare
  now timestamptz = now(); -- here for brevity since now() is fixed in a transaction anyway
  current_user_id uuid = coalesce(private.current_user_id(), '68c539ac-c89c-456e-baf3-92082ed452a6'); -- whenever user is not authenticated, its the backend system Rechnungsextraktion performing changes
  prev_invoice public.invoice;
  next_invoice public.invoice;
  prev_other_document public.other_document;
  next_other_document public.other_document;
begin
  case tg_table_name
    when 'invoice'
    then
      next_invoice := new;
      if tg_op = 'UPDATE'
      then
        prev_invoice := old;
      end if;

      if prev_invoice.partner_company_id is distinct from next_invoice.partner_company_id
      then
        insert into public.document_field_value_partner_company (field_id, document_id, value, created_by, created_at)
        values ('02dc8742-60ea-459f-9df1-d132cc1905eb', next_invoice.document_id, next_invoice.partner_company_id, current_user_id, now);
      end if;

      if prev_invoice.partner_company_location_id is distinct from next_invoice.partner_company_location_id
      then
        insert into public.document_field_value_company_location (field_id, document_id, value, created_by, created_at)
        values ('0b6d135d-7ce1-43e0-a135-37929a7697b6', next_invoice.document_id, next_invoice.partner_company_location_id, current_user_id, now);
      end if;

      if prev_invoice.invoice_number is distinct from next_invoice.invoice_number
      then
        insert into public.document_field_value_text (field_id, document_id, value, created_by, created_at)
        values ('9633c569-7119-40bc-9113-0a6604daecd3', next_invoice.document_id, next_invoice.invoice_number, current_user_id, now);
      end if;

      if prev_invoice.order_number is distinct from next_invoice.order_number
      then
        insert into public.document_field_value_text (field_id, document_id, value, created_by, created_at)
        values ('f1adeead-efc1-4d34-b06e-84d47ad6a461', next_invoice.document_id, next_invoice.order_number, current_user_id, now);
      end if;

      if prev_invoice.internal_number is distinct from next_invoice.internal_number
      then
        insert into public.document_field_value_text (field_id, document_id, value, created_by, created_at)
        values ('ec32c90f-ea47-485b-b59a-db4950109296', next_invoice.document_id, next_invoice.internal_number, current_user_id, now);
      end if;

      if prev_invoice.invoice_date is distinct from next_invoice.invoice_date
      then
        insert into public.document_field_value_date (field_id, document_id, value, created_by, created_at)
        values ('f657537d-be72-42af-b3fc-08f7a676e7da', next_invoice.document_id, next_invoice.invoice_date, current_user_id, now);
      end if;

      if prev_invoice.order_date is distinct from next_invoice.order_date
      then
        insert into public.document_field_value_date (field_id, document_id, value, created_by, created_at)
        values ('6822eedf-1092-4bca-baa5-e225b720b4f5', next_invoice.document_id, next_invoice.order_date, current_user_id, now);
      end if;

      if prev_invoice.net is distinct from next_invoice.net
      then
        insert into public.document_field_value_number (field_id, document_id, value, created_by, created_at)
        values ('f82cdb8a-1d93-4c80-a5a3-354dec8bd7e7', next_invoice.document_id, next_invoice.net, current_user_id, now);
      end if;

      if prev_invoice.total is distinct from next_invoice.total
      then
        insert into public.document_field_value_number (field_id, document_id, value, created_by, created_at)
        values ('224dc2a8-2550-4c06-89b7-7610c71afeef', next_invoice.document_id, next_invoice.total, current_user_id, now);
      end if;

      if prev_invoice.vat_percent is distinct from next_invoice.vat_percent
      then
        insert into public.document_field_value_number (field_id, document_id, value, created_by, created_at)
        values ('1917fa18-dffd-4739-9755-491c6eb9b8c1', next_invoice.document_id, next_invoice.vat_percent, current_user_id, now);
      end if;

      if prev_invoice.discount_percent is distinct from next_invoice.discount_percent
      then
        insert into public.document_field_value_number (field_id, document_id, value, created_by, created_at)
        values ('dab9fc7f-003a-4be4-9d7b-c3d7d7ea4c75', next_invoice.document_id, next_invoice.discount_percent, current_user_id, now);
      end if;

      if prev_invoice.discount_amount is distinct from next_invoice.discount_amount
      then
        insert into public.document_field_value_number (field_id, document_id, value, created_by, created_at)
        values ('0554c279-3ac7-4cdf-9352-bf47453fba7e', next_invoice.document_id, next_invoice.discount_amount, current_user_id, now);
      end if;

      if prev_invoice.discount_until is distinct from next_invoice.discount_until
      then
        insert into public.document_field_value_date (field_id, document_id, value, created_by, created_at)
        values ('096ce5a9-e25a-4a5e-b8b7-501841b68e8b', next_invoice.document_id, next_invoice.discount_until, current_user_id, now);
      end if;

      if prev_invoice.currency is distinct from next_invoice.currency
      then
        insert into public.document_field_value_currency (field_id, document_id, value, created_by, created_at)
        values ('768984ed-cfb7-4526-95b3-a1bafe65cac4', next_invoice.document_id, next_invoice.currency, current_user_id, now);
      end if;

      if prev_invoice.goods_services is distinct from next_invoice.goods_services
      then
        insert into public.document_field_value_text (field_id, document_id, value, created_by, created_at)
        values ('4cfc4804-240a-4d75-82e7-e1b08ddb2b59', next_invoice.document_id, next_invoice.goods_services, current_user_id, now);
      end if;

      if prev_invoice.delivered_from is distinct from next_invoice.delivered_from
      then
        insert into public.document_field_value_date (field_id, document_id, value, created_by, created_at)
        values ('772a840d-ac58-4225-bd97-1590c4b0e219', next_invoice.document_id, next_invoice.delivered_from, current_user_id, now);
      end if;

      if prev_invoice.delivered_until is distinct from next_invoice.delivered_until
      then
        insert into public.document_field_value_date (field_id, document_id, value, created_by, created_at)
        values ('6da83820-67f2-4c1f-8924-bc50cd64c1f4', next_invoice.document_id, next_invoice.delivered_until, current_user_id, now);
      end if;

      if prev_invoice.iban is distinct from next_invoice.iban
      then
        insert into public.document_field_value_iban (field_id, document_id, value, created_by, created_at)
        values ('63857169-2a58-4585-96a9-343aa99b2577', next_invoice.document_id, next_invoice.iban, current_user_id, now);
      end if;

      if prev_invoice.bic is distinct from next_invoice.bic
      then
        insert into public.document_field_value_bic (field_id, document_id, value, created_by, created_at)
        values ('09a8bcad-9890-44b6-ae6d-beb299ded869', next_invoice.document_id, next_invoice.bic, current_user_id, now);
      end if;

      if prev_invoice.due_date is distinct from next_invoice.due_date
      then
        insert into public.document_field_value_date (field_id, document_id, value, created_by, created_at)
        values ('8ae1d065-61f6-4092-9b99-8b40d55a0570', next_invoice.document_id, next_invoice.due_date, current_user_id, now);
      end if;

      if prev_invoice.payment_status is distinct from next_invoice.payment_status
      then
        insert into public.document_field_value_invoice_payment_status (field_id, document_id, value, created_by, created_at)
        values ('cb5b3534-7f83-4087-ba1e-dd05b0e556e7', next_invoice.document_id, next_invoice.payment_status, current_user_id, now);
      end if;

      if prev_invoice.payment_reference is distinct from next_invoice.payment_reference
      then
        insert into public.document_field_value_text (field_id, document_id, value, created_by, created_at)
        values ('b415b6b5-9fc6-48d7-84ff-8f64646fede5', next_invoice.document_id, next_invoice.payment_reference, current_user_id, now);
      end if;

      if prev_invoice.paid_date is distinct from next_invoice.paid_date
      then
        insert into public.document_field_value_date (field_id, document_id, value, created_by, created_at)
        values ('6fbe01d1-6ee7-47e1-b58b-4188597d2f7b', next_invoice.document_id, next_invoice.paid_date, current_user_id, now);
      end if;

      if prev_invoice.credit_memo is distinct from next_invoice.credit_memo
      then
        insert into public.document_field_value_boolean (field_id, document_id, value, created_by, created_at)
        values ('a0279fbc-28f0-4fae-b717-144ce9f2136c', next_invoice.document_id, next_invoice.credit_memo, current_user_id, now);
      end if;

      if prev_invoice.credit_memo_for_invoice_document_id is distinct from next_invoice.credit_memo_for_invoice_document_id
      then
        insert into public.document_field_value_invoice (field_id, document_id, value, created_by, created_at)
        values ('5db1d952-7d7f-4bd1-bd28-e056814e14d9', next_invoice.document_id, next_invoice.credit_memo_for_invoice_document_id, current_user_id, now);
      end if;

      if prev_invoice.partially_paid is distinct from next_invoice.partially_paid
      then
        insert into public.document_field_value_boolean (field_id, document_id, value, created_by, created_at)
        values ('bbbb3e2c-14ee-436c-9ade-f278d9ecd2b6', next_invoice.document_id, next_invoice.partially_paid, current_user_id, now);
      end if;

    when 'other_document'
    then
      next_other_document := new;
      if tg_op = 'UPDATE'
      then
        prev_other_document := old;
      end if;

      if prev_other_document."type" is distinct from next_other_document."type"
      then
        insert into public.document_field_value_other_document_type (field_id, document_id, value, created_by, created_at)
        values ('9ce46ec4-8d7e-4593-9c72-9f1041e2e5f9', next_other_document.document_id, next_other_document."type", current_user_id, now);
      end if;

      if prev_other_document.partner_company_id is distinct from next_other_document.partner_company_id
      then
        insert into public.document_field_value_partner_company (field_id, document_id, value, created_by, created_at)
        values ('02dc8742-60ea-459f-9df1-d132cc1905eb', next_other_document.document_id, next_other_document.partner_company_id, current_user_id, now);
      end if;

      if prev_other_document.document_date is distinct from next_other_document.document_date
      then
        insert into public.document_field_value_date (field_id, document_id, value, created_by, created_at)
        values ('4de2e5c4-b13c-4897-94ed-661e42f9a1d4', next_other_document.document_id, next_other_document.document_date, current_user_id, now);
      end if;

      if prev_other_document.document_number is distinct from next_other_document.document_number
      then
        insert into public.document_field_value_text (field_id, document_id, value, created_by, created_at)
        values ('8e52a496-1dc1-4604-9ed2-ef5ca0aedd7f', next_other_document.document_id, next_other_document.document_number, current_user_id, now);
      end if;

      if prev_other_document.resubmission_date is distinct from next_other_document.resubmission_date
      then
        insert into public.document_field_value_date (field_id, document_id, value, created_by, created_at)
        values ('95f56b03-0061-48ad-bc90-039394deb9bc', next_other_document.document_id, next_other_document.resubmission_date, current_user_id, now);
      end if;

      if prev_other_document.expiry_date is distinct from next_other_document.expiry_date
      then
        insert into public.document_field_value_date (field_id, document_id, value, created_by, created_at)
        values ('16603cbc-4371-4735-86e7-4a649cadb2bd', next_other_document.document_id, next_other_document.expiry_date, current_user_id, now);
      end if;

      if prev_other_document.contract_type is distinct from next_other_document.contract_type
      then
        insert into public.document_field_value_other_document_contract_type (field_id, document_id, value, created_by, created_at)
        values ('aaa53680-1c6c-40cb-9ec4-17e670f8028f', next_other_document.document_id, next_other_document.contract_type, current_user_id, now);
      end if;

      if prev_other_document.document_details is distinct from next_other_document.document_details
      then
        insert into public.document_field_value_text (field_id, document_id, value, created_by, created_at)
        values ('3be7bdb3-b7bb-482f-a7e4-50fe81afdc2c', next_other_document.document_id, next_other_document.document_details, current_user_id, now);
      end if;

      if prev_other_document.contact_user_id is distinct from next_other_document.contact_user_id
      then
        insert into public.document_field_value_text (field_id, document_id, value, created_by, created_at)
        values ('8e1f6e62-a2cd-4e10-8a64-19047f3939b0', next_other_document.document_id, next_other_document.contact_user_id::non_empty_text, current_user_id, now);
      end if;

    else
      raise exception 'Unsupported table % for document field values sync', tg_table_name;
  end case;

  return null;
end
$$ language plpgsql volatile;

create trigger sync_document_field_values_on_invoice_change
  after insert or update on public.invoice
  for each row
  execute function public.sync_document_field_values();

create trigger sync_document_field_values_on_other_document_change
  after insert or update on public.other_document
  for each row
  execute function public.sync_document_field_values();
