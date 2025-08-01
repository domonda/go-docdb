-- TODO-db-210322 confirmed_by should always reference the users table
create function private.user_id_for_invoice_confirmed_by(
    confirmed_by text
) returns uuid as $$
begin
    case
        when confirmed_by in ('BluDelta', 'bludelta_v2', 'DOMONDA_EXTRACTION')
        then return '68c539ac-c89c-456e-baf3-92082ed452a6';
        when confirmed_by = 'ABACUS'
        then return 'd59e5071-3f08-4091-b5a9-bb9da199f688';
        when confirmed_by = 'BILLOMAT'
        then return 'c8ee802b-7605-4095-87b7-d5db56c7b0af';
        when confirmed_by = 'FASTBILL'
        then return '979f0d19-f247-4763-8b5f-1fceded2a34b';
        else return confirmed_by::uuid;
    end case;
exception when others then
    return null;
end
$$ language plpgsql immutable strict;

create function private.user_for_invoice_confirmed_by(
    confirmed_by text
) returns public.user as $$
    select "user".* from public.user
    where "user".id = private.user_id_for_invoice_confirmed_by(confirmed_by)
$$ language sql stable strict;

----

create function public.invoice_partner_company_id_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.partner_company_id_confirmed_by)
$$ language sql stable strict;

create function public.invoice_partner_company_id_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.partner_company_id_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_invoice_number_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.invoice_number_confirmed_by)
$$ language sql stable strict;

create function public.invoice_invoice_number_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.invoice_number_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_internal_number_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.internal_number_confirmed_by)
$$ language sql stable strict;

create function public.invoice_internal_number_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.internal_number_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_order_number_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.order_number_confirmed_by)
$$ language sql stable strict;

create function public.invoice_order_number_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.order_number_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_invoice_date_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.invoice_date_confirmed_by)
$$ language sql stable strict;

create function public.invoice_invoice_date_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.invoice_date_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_order_date_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.order_date_confirmed_by)
$$ language sql stable strict;

create function public.invoice_order_date_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.order_date_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_currency_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.currency_confirmed_by)
$$ language sql stable strict;

create function public.invoice_currency_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.currency_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_net_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.net_confirmed_by)
$$ language sql stable strict;

create function public.invoice_net_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.net_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_total_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.total_confirmed_by)
$$ language sql stable strict;

create function public.invoice_total_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.total_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_payment_status_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.payment_status_confirmed_by)
$$ language sql stable strict;

create function public.invoice_payment_status_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.payment_status_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_paid_date_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.paid_date_confirmed_by)
$$ language sql stable strict;

create function public.invoice_paid_date_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.paid_date_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_due_date_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.due_date_confirmed_by)
$$ language sql stable strict;

create function public.invoice_due_date_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.due_date_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_discount_until_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.discount_until_confirmed_by)
$$ language sql stable strict;

create function public.invoice_discount_until_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.discount_until_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_discount_percent_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.discount_percent_confirmed_by)
$$ language sql stable strict;

create function public.invoice_discount_percent_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.discount_percent_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_discount_amount_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.discount_amount_confirmed_by)
$$ language sql stable strict;

create function public.invoice_discount_amount_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.discount_amount_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_iban_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.iban_confirmed_by)
$$ language sql stable strict;

create function public.invoice_iban_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.iban_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_bic_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.bic_confirmed_by)
$$ language sql stable strict;

create function public.invoice_bic_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.bic_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_payment_reference_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.payment_reference_confirmed_by)
$$ language sql stable strict;

create function public.invoice_payment_reference_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.payment_reference_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_delivered_from_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.delivered_from_confirmed_by)
$$ language sql stable strict;

create function public.invoice_delivered_from_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.delivered_from_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_delivered_until_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select *
    from private.user_for_invoice_confirmed_by(invoice.delivered_until_confirmed_by)
$$ language sql stable strict;

create function public.invoice_delivered_until_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.delivered_until_confirmed_at
$$ language sql stable strict;

----

create function public.invoice_partially_paid_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select * from public.user where id = invoice.partially_paid_confirmed_by
$$ language sql stable strict;

create function public.invoice_partially_paid_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select invoice.partially_paid_confirmed_at
$$ language sql immutable strict;

----

create function public.invoice_accounting_items_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select coalesce(updated_user, created_user) from public.invoice_accounting_item
        left join public.user as updated_user on updated_user.id = invoice_accounting_item.updated_by
        inner join public.user as created_user on created_user.id = invoice_accounting_item.created_by
    where invoice_accounting_item.invoice_document_id = invoice.document_id
    order by
        invoice_accounting_item.updated_by nulls last,
        invoice_accounting_item.updated_at desc
    limit 1
$$ language sql stable strict;

create function public.invoice_accounting_items_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select updated_at from public.invoice_accounting_item
    where invoice_accounting_item.invoice_document_id = invoice.document_id
    order by updated_at desc
    limit 1
$$ language sql stable strict;

----

create function private.invoice_last_edit(
    invoice public.invoice
) returns record as $$
declare
    last_at timestamptz;
    last_by public.user;
begin
    -- start with the partner last edit at
    last_at := public.invoice_partner_company_id_last_edit_at(invoice);
    last_by := public.invoice_partner_company_id_last_edit_by(invoice);

    if last_at is null or last_at < public.invoice_invoice_number_last_edit_at(invoice) then
        last_at := public.invoice_invoice_number_last_edit_at(invoice);
        last_by := public.invoice_invoice_number_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_order_number_last_edit_at(invoice) then
        last_at := public.invoice_order_number_last_edit_at(invoice);
        last_by := public.invoice_order_number_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_invoice_date_last_edit_at(invoice) then
        last_at := public.invoice_invoice_date_last_edit_at(invoice);
        last_by := public.invoice_invoice_date_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_order_date_last_edit_at(invoice) then
        last_at := public.invoice_order_date_last_edit_at(invoice);
        last_by := public.invoice_order_date_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_currency_last_edit_at(invoice) then
        last_at := public.invoice_currency_last_edit_at(invoice);
        last_by := public.invoice_currency_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_net_last_edit_at(invoice) then
        last_at := public.invoice_net_last_edit_at(invoice);
        last_by := public.invoice_net_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_total_last_edit_at(invoice) then
        last_at := public.invoice_total_last_edit_at(invoice);
        last_by := public.invoice_total_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_payment_status_last_edit_at(invoice) then
        last_at := public.invoice_payment_status_last_edit_at(invoice);
        last_by := public.invoice_payment_status_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_paid_date_last_edit_at(invoice) then
        last_at := public.invoice_paid_date_last_edit_at(invoice);
        last_by := public.invoice_paid_date_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_due_date_last_edit_at(invoice) then
        last_at := public.invoice_due_date_last_edit_at(invoice);
        last_by := public.invoice_due_date_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_discount_until_last_edit_at(invoice) then
        last_at := public.invoice_discount_until_last_edit_at(invoice);
        last_by := public.invoice_discount_until_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_discount_percent_last_edit_at(invoice) then
        last_at := public.invoice_discount_percent_last_edit_at(invoice);
        last_by := public.invoice_discount_percent_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_discount_amount_last_edit_at(invoice) then
        last_at := public.invoice_discount_amount_last_edit_at(invoice);
        last_by := public.invoice_discount_amount_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_iban_last_edit_at(invoice) then
        last_at := public.invoice_iban_last_edit_at(invoice);
        last_by := public.invoice_iban_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_bic_last_edit_at(invoice) then
        last_at := public.invoice_bic_last_edit_at(invoice);
        last_by := public.invoice_bic_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_payment_reference_last_edit_at(invoice) then
        last_at := public.invoice_payment_reference_last_edit_at(invoice);
        last_by := public.invoice_payment_reference_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_delivered_from_last_edit_at(invoice) then
        last_at := public.invoice_delivered_from_last_edit_at(invoice);
        last_by := public.invoice_delivered_from_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_delivered_until_last_edit_at(invoice) then
        last_at := public.invoice_delivered_until_last_edit_at(invoice);
        last_by := public.invoice_delivered_until_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_accounting_items_last_edit_at(invoice) then
        last_at := public.invoice_accounting_items_last_edit_at(invoice);
        last_by := public.invoice_accounting_items_last_edit_by(invoice);
    end if;

    if last_at is null or last_at < public.invoice_partially_paid_last_edit_at(invoice) then
        last_at := public.invoice_partially_paid_last_edit_at(invoice);
        last_by := public.invoice_partially_paid_last_edit_by(invoice);
    end if;

    -- null record is different from null value
    if last_by is null then return null; end if;
    return (last_by.id, last_at);
end
$$ language plpgsql stable strict;

create function public.invoice_last_edit_by(
    invoice public.invoice
) returns public.user as $$
    select "user".* from private.invoice_last_edit(invoice) as (by uuid, at timestamptz)
        inner join public."user" on "user".id = by
$$ language sql stable strict;
comment on function public.invoice_last_edit_by is 'Last edit on _any_ invoice field performed by.';

create function public.invoice_last_edit_at(
    invoice public.invoice
) returns timestamptz as $$
    select at from private.invoice_last_edit(invoice) as (by uuid, at timestamptz)
$$ language sql stable strict;
comment on function public.invoice_last_edit_at is 'Last edit on _any_ invoice field performed at.';
