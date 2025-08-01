create view api.invoice with (security_barrier) as
    select
        i.document_id,
        i.unresolved_issues,
        i.unresolved_issues_desc,
        i.accountant_lock_by,
        i.accountant_lock_at,
        i.booked_by,
        i.booked_at,
        i.partner_company_id,
        i.partner_company_id_confirmed_by,
        i.partner_company_id_confirmed_at,
        i.partner_company_location_id,
        i.partner_company_location_id_confirmed_by,
        i.partner_company_location_id_confirmed_at,
        i.invoice_number,
        i.invoice_number_confirmed_by,
        i.invoice_number_confirmed_at,
        i.order_number,
        i.order_number_confirmed_by,
        i.order_number_confirmed_at,
        i.internal_number,
        i.internal_number_confirmed_by,
        i.internal_number_confirmed_at,
        i.invoice_date,
        i.invoice_date_confirmed_by,
        i.invoice_date_confirmed_at,
        i.order_date,
        i.order_date_confirmed_by,
        i.order_date_confirmed_at,
        i.net,
        i.net_confirmed_by,
        i.net_confirmed_at,
        i.total,
        i.total_confirmed_by,
        i.total_confirmed_at,
        i.vat_percent,
        i.vat_percent_confirmed_by,
        i.vat_percent_confirmed_at,
        i.vat_percentages,
        i.discount_percent,
        i.discount_percent_confirmed_by,
        i.discount_percent_confirmed_at,
        i.discount_amount,
        i.discount_amount_confirmed_by,
        i.discount_amount_confirmed_at,
        i.discount_until,
        i.discount_until_confirmed_by,
        i.discount_until_confirmed_at,
        i.currency,
        i.currency_confirmed_by,
        i.currency_confirmed_at,
        i.conversion_rate,
        i.conversion_rate_date,
        i.conversion_rate_source,
        i.goods_services,
        i.goods_services_confirmed_by,
        i.goods_services_confirmed_at,
        i.delivered_from,
        i.delivered_from_confirmed_by,
        i.delivered_from_confirmed_at,
        i.delivered_until,
        i.delivered_until_confirmed_by,
        i.delivered_until_confirmed_at,
        i.iban,
        i.iban_confirmed_by,
        i.iban_confirmed_at,
        i.iban_candidates,
        i.bic,
        i.bic_confirmed_by,
        i.bic_confirmed_at,
        i.bic_candidates,
        i.due_date,
        i.due_date_confirmed_by,
        i.due_date_confirmed_at,
        i.payment_status,
        i.payment_status_confirmed_by,
        i.payment_status_confirmed_at,
        i.payment_reference,
        i.payment_reference_confirmed_by,
        i.payment_reference_confirmed_at,
        i.pay_from_bank_account_id,
        i.pay_from_bank_account_id_confirmed_by,
        i.pay_from_bank_account_id_confirmed_at,
        i.paid_date,
        i.paid_date_confirmed_by,
        i.paid_date_confirmed_at,
        i.credit_memo,
        i.credit_memo_confirmed_by,
        i.credit_memo_confirmed_at,
        i.credit_memo_for_invoice_document_id,
        i.credit_memo_for_invoice_document_id_confirmed_by,
        i.credit_memo_for_invoice_document_id_confirmed_at,
        i.override_partner_company_payment_preset,
        i.override_partner_company_payment_preset_by,
        i.override_partner_company_payment_preset_at,
        i.partially_paid,
        i.partially_paid_confirmed_by,
        i.partially_paid_confirmed_at,
        i.delivery_note_numbers,
        i.delivery_note_numbers_confirmed_by,
        i.delivery_note_numbers_confirmed_at,
        i.open_items_number,
        i.open_items_number_confirmed_by,
        i.open_items_number_confirmed_at,
        i.ger_clause_35a_net,
        i.ger_clause_35a_net_confirmed_by,
        i.ger_clause_35a_net_confirmed_at,
        i.ger_clause_35a_total,
        i.ger_clause_35a_total_confirmed_by,
        i.ger_clause_35a_total_confirmed_at,
        i.ger_clause_35a_kind,
        i.ger_clause_35a_kind_confirmed_by,
        i.ger_clause_35a_kind_confirmed_at,
        i.updated_at,
        i.created_at
    from public.invoice as i
        join api.document as d on (d.id = i.document_id);

grant select on table api.invoice to domonda_api;

comment on column api.invoice.currency is '@notNull';
comment on column api.invoice.credit_memo is '@notNull';
comment on column api.invoice.payment_status is 'How the invoice was paid, selected by the user in the App UI. Use `Document.paymentStatus` to get a consolidated status including matched money transactions.';
comment on column api.invoice.paid_date is 'When the invoice was paid, entered by the user in the App UI.';
comment on column api.invoice.partially_paid is '@notNull';
comment on column api.invoice.override_partner_company_payment_preset is 'Should the `Invoice` payment details take precedence over any `PartnerCompanyPaymentPreset`.';
comment on column api.invoice.ger_clause_35a_net is 'German real estate law clause 35a net amount relevant for real estate service invoices.';
comment on column api.invoice.ger_clause_35a_total is 'German real estate law clause 35a total amount relevant for real estate service invoices.';
comment on column api.invoice.ger_clause_35a_kind is 'German real estate law clause 35a kind. Can be "MARGINAL_EMPLOYMENT", "ENSURED_EMPLOYMENT", "HOUSEHOLD_SERVICES", "CRAFTSMAN_SERVICES".';
comment on column api.invoice.updated_at is E'@notNull\nTime of last update.';
comment on column api.invoice.created_at is E'@notNull\nCreation time of object.';

comment on view api.invoice is $$
@primaryKey document_id
@foreignKey (document_id) references api.document (id)
@foreignKey (partner_company_id) references api.partner_company (id)
@foreignKey (partner_company_location_id) references api.company_location (id)
@foreignKey (credit_memo_for_invoice_document_id) references api.invoice (document_id)
@foreignKey (pay_from_bank_account_id) references api.bank_account (id)
A `Document` representing an `Invoice`.$$;

----

create function api.invoice_total_in_eur(
    invoice api.invoice
) returns float8 as
$$
    select invoice.total / coalesce(invoice.conversion_rate, 1)
$$
language sql immutable;

comment on function api.invoice_total_in_eur is E'Total converted to euros.';

----

create function api.invoice_payment_due_date(
    invoice api.invoice
) returns date as $$
    select public.invoice_payment_due_date(inv)
    from public.invoice as inv
    where inv.document_id = invoice_payment_due_date.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_payment_discount_due_date(
    invoice api.invoice
) returns date as $$
    select public.invoice_payment_discount_due_date(inv)
    from public.invoice as inv
    where inv.document_id = invoice_payment_discount_due_date.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_payment_discount_percent(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_payment_discount_percent(inv)
    from public.invoice as inv
    where inv.document_id = invoice_payment_discount_percent.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_payment_discount_amount(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_payment_discount_amount(inv)
    from public.invoice as inv
    where inv.document_id = invoice_payment_discount_amount.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_payment_discount_net_amount(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_payment_discount_net_amount(inv)
    from public.invoice as inv
    where inv.document_id = invoice_payment_discount_net_amount.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_payment_discount_total_amount(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_payment_discount_total_amount(inv)
    from public.invoice as inv
    where inv.document_id = invoice_payment_discount_total_amount.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_total_with_payment_discount(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_total_with_payment_discount(inv)
    from public.invoice as inv
    where inv.document_id = invoice_total_with_payment_discount.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_converted_total_with_payment_discount(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_converted_total_with_payment_discount(inv)
    from public.invoice as inv
    where inv.document_id = invoice_converted_total_with_payment_discount.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_converted_signed_total_with_payment_discount(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_converted_signed_total_with_payment_discount(inv)
    from public.invoice as inv
    where inv.document_id = invoice_converted_signed_total_with_payment_discount.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_converted_discounted_total(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_converted_discounted_total(inv)
    from public.invoice as inv
    where inv.document_id = invoice_converted_discounted_total.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_converted_signed_discounted_total(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_converted_signed_discounted_total(inv)
    from public.invoice as inv
    where inv.document_id = invoice_converted_signed_discounted_total.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_credit_memos_total_with_payment_discount_sum(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_credit_memos_total_with_payment_discount_sum(inv)
    from public.invoice as inv
    where inv.document_id = invoice_credit_memos_total_with_payment_discount_sum.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_credit_memos_converted_signed_discounted_total_sum(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_credit_memos_converted_signed_discounted_total_sum(inv)
    from public.invoice as inv
    where inv.document_id = invoice_credit_memos_converted_signed_discounted_total_sum.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_money_transactions_amount_sum(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_money_transactions_amount_sum(inv)
    from public.invoice as inv
    where inv.document_id = invoice_money_transactions_amount_sum.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_money_transactions_signed_amount_sum(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_money_transactions_signed_amount_sum(inv)
    from public.invoice as inv
    where inv.document_id = invoice_money_transactions_signed_amount_sum.invoice.document_id
$$ language sql stable strict security definer;

create function api.invoice_open_amount(
    invoice api.invoice
) returns float8 as $$
    select public.invoice_open_amount(inv)
    from public.invoice as inv
    where inv.document_id = invoice_open_amount.invoice.document_id
$$ language sql stable strict security definer;

----

create function api.invoice_partner_name(
    invoice api.invoice
) returns text as $$
    select public.invoice_partner_name(inv)
    from public.invoice as inv
    where inv.document_id = invoice_partner_name.invoice.document_id
$$ language sql stable strict security definer;

comment on function api.invoice_partner_name is 'Partner name from the linked partner company.';

create function api.invoice_partner_vat_id_no(
    invoice api.invoice
) returns text as $$
    select public.invoice_partner_vat_id_no(inv)
    from public.invoice as inv
    where inv.document_id = invoice_partner_vat_id_no.invoice.document_id
$$ language sql stable strict security definer;

comment on function api.invoice_partner_vat_id_no is 'Partner VAT-ID number derived from the main address of the linked partner company.';

----

create function api.update_invoice_payment_status(
  invoice_document_id         uuid,
  payment_status              public.invoice_payment_status,
  payment_status_confirmed_by text = 'API'
) returns api.invoice as $$
    with updated as (
        update public.invoice
        set
            payment_status=update_invoice_payment_status.payment_status,
            payment_status_confirmed_by=update_invoice_payment_status.payment_status_confirmed_by,
            payment_status_confirmed_at=now(),
            updated_at=now()
        where invoice.document_id = invoice_document_id
        returning document_id
    )
    select * from api.invoice
    where document_id = (select document_id from updated)
$$ language sql security definer;

comment on function api.update_invoice_payment_status is 'Updates the `paymentStatus` of an `Invoice`.';


create function api.update_invoice_number(
  invoice_document_id uuid,
  invoice_number      text,
  confirmed_by        text = 'API'
) returns api.invoice as $$
    with updated as (
        update public.invoice
        set
            invoice_number             =update_invoice_number.invoice_number,
            invoice_number_confirmed_by=update_invoice_number.confirmed_by,
            invoice_number_confirmed_at=now(),
            updated_at                 =now()
        where document_id = invoice_document_id
        returning document_id
    )
    select * from api.invoice
    where document_id = (select document_id from updated)
$$ language sql security definer;

comment on function api.update_invoice_number is 'Updates the `invoiceNumber` of an `Invoice`.';


create function api.update_invoice_order_number(
  invoice_document_id uuid,
  order_number        text,
  confirmed_by        text = 'API'
) returns api.invoice as $$
    with updated as (
        update public.invoice
        set
            order_number             =update_invoice_order_number.order_number::non_empty_text,
            order_number_confirmed_by=update_invoice_order_number.confirmed_by,
            order_number_confirmed_at=now(),
            updated_at               =now()
        where document_id = invoice_document_id
        returning document_id
    )
    select * from api.invoice
    where document_id = (select document_id from updated)
$$ language sql security definer;

comment on function api.update_invoice_order_number is 'Updates the `orderNumber` of an `Invoice`.';


create function api.update_invoice_internal_number(
  invoice_document_id uuid,
  internal_number     text,
  confirmed_by        text = 'API'
) returns api.invoice as $$
    with updated as (
        update public.invoice
        set
            internal_number             =update_invoice_internal_number.internal_number,
            internal_number_confirmed_by=update_invoice_internal_number.confirmed_by,
            internal_number_confirmed_at=now(),
            updated_at                  =now()
        where document_id = invoice_document_id
        returning document_id
    )
    select * from api.invoice
    where document_id = (select document_id from updated)
$$ language sql security definer;

comment on function api.update_invoice_internal_number is 'Updates the `internalNumber` of an `Invoice`.';


create function api.update_invoice_date(
  invoice_document_id uuid,
  invoice_date        date,
  confirmed_by        text = 'API'
) returns api.invoice as $$
    with updated as (
        update public.invoice
        set
            invoice_date             =update_invoice_date.invoice_date,
            invoice_date_confirmed_by=update_invoice_date.confirmed_by,
            invoice_date_confirmed_at=now(),
            updated_at               =now()
        where document_id = invoice_document_id
        returning document_id
    )
    select * from api.invoice
    where document_id = (select document_id from updated)
$$ language sql security definer;

comment on function api.update_invoice_date is 'Updates the `invoiceDate` of an `Invoice`.';


create function api.update_invoice_order_date(
  invoice_document_id uuid,
  order_date          date,
  confirmed_by        text = 'API'
) returns api.invoice as $$
    with updated as (
        update public.invoice
        set
            order_date             =update_invoice_order_date.order_date,
            order_date_confirmed_by=update_invoice_order_date.confirmed_by,
            order_date_confirmed_at=now(),
            updated_at             =now()
        where document_id = invoice_document_id
        returning document_id
    )
    select * from api.invoice
    where document_id = (select document_id from updated)
$$ language sql security definer;

comment on function api.update_invoice_order_date is 'Updates the `orderDate` of an `Invoice`.';


create function api.update_invoice_open_items_number(
  invoice_document_id uuid,
  open_items_number   text,
  confirmed_by        text = 'API'
) returns api.invoice as $$
    with updated as (
        update public.invoice
        set
            open_items_number             =update_invoice_open_items_number.open_items_number::trimmed_text,
            open_items_number_confirmed_by=update_invoice_open_items_number.confirmed_by,
            open_items_number_confirmed_at=now(),
            updated_at                    =now()
        where document_id = invoice_document_id
        returning document_id
    )
    select * from api.invoice
    where document_id = (select document_id from updated)
$$ language sql security definer;

comment on function api.update_invoice_open_items_number is 'Updates the `openItemsNumber` of an `Invoice`.';


create function api.update_invoice_delivery_note_numbers(
  invoice_document_id   uuid,
  delivery_note_numbers text[],
  confirmed_by          text = 'API'
) returns api.invoice as $$
    with updated as (
        update public.invoice
        set
            delivery_note_numbers             =update_invoice_delivery_note_numbers.delivery_note_numbers,
            delivery_note_numbers_confirmed_by=update_invoice_delivery_note_numbers.confirmed_by::trimmed_text,
            delivery_note_numbers_confirmed_at=now(),
            updated_at                        =now()
        where document_id = invoice_document_id
        returning document_id
    )
    select * from api.invoice
    where document_id = (select document_id from updated)
$$ language sql security definer;

comment on function api.update_invoice_delivery_note_numbers is 'Updates the `deliveryNoteNumbers` of an `Invoice`.';
