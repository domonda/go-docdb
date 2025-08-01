create function public.document_is_visible(
    doc public.document
) returns boolean as
$$
    select (doc.superseded is false) and (doc.num_pages > 0)
$$
language sql stable;

comment on function public.document_is_visible(public.document) is 'If document should be shown to user';

grant execute on function public.document_is_visible(public.document) to domonda_user;

----

create function public.document_is_checked_out(
    doc public.document
) returns boolean as
$$
    select doc.checkout_user_id is not null
$$
language sql stable;

comment on function public.document_is_checked_out(public.document) is 'Returns if the document has been checked out by a user';

grant execute on function public.document_is_checked_out(public.document) to domonda_user;

----

create function public.document_is_processing(
    doc public.document
) returns boolean as
$$
    select (doc.num_pages = 0)
$$
language sql stable;

comment on function public.document_is_processing(public.document) is 'If document is currently undergoing processing';

grant execute on function public.document_is_processing(public.document) to domonda_user;

----

create function public.document_can_add_money_transactions(
    document public.document
) returns boolean as
$$
    select (
        exists (
            select 1 from public.money_account where (client_company_id = document.client_company_id)
        )
    ) and (
        exists (
            select 1 from public.document_category
            where (
                id = document.category_id
            ) and (
                (document_type = 'INCOMING_INVOICE') or (document_type = 'OUTGOING_INVOICE')
            )
        )
    ) and (
        exists (
            select 1 from public.invoice
            where (
                document_id = document.id
            ) and (
                (
                    payment_status is null
                ) or (
                    payment_status = 'CREDITCARD'
                ) or (
                    payment_status = 'BANK'
                ) or (
                    payment_status = 'PAYPAL'
                ) or (
                    payment_status = 'TRANSFERWISE'
                ) or (
                    payment_status = 'DIRECT_DEBIT'
                )
                -- TODO: add matching `cash_transactions`
            )
        )
    ) and (
        case public.document_state(document)
            when 'DELETED' then false
            when 'SUPERSEDED' then false
            when 'IN_RESTRUCTURE_GROUP' then false
            else true
        end
    )
$$
language sql stable strict;

comment on function public.document_can_add_money_transactions is 'If the `Document` is eligible for having money transactions added/matched.';

----

-- TODO-db-200618 derive also `public.delivery_note`
create function public.document_derived_title(
    document public.document
) returns text as $$
    select coalesce(
        (
            select coalesce(
                public.invoice_partner_name(invoice) || ': ' || invoice.invoice_number,
                public.invoice_partner_name(invoice),
                invoice.invoice_number
            )
            from public.invoice
            where invoice.document_id = document.id
        ),
        (
            select coalesce(
                public.other_document_partner_name(other_document) || ': ' || other_document.document_number,
                public.other_document_partner_name(other_document),
                other_document.document_number
            )
            from public.other_document
            where other_document.document_id = document.id
        ),
        document.title,
        document.name
    )
$$ language sql stable;

comment on function public.document_derived_title is E'@notNull\nTitle of the `Document` properly derived from its data.';
