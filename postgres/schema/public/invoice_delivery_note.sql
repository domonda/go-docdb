create table public.invoice_delivery_note (
    invoice_document_id       uuid not null references public.invoice(document_id) on delete cascade,
    delivery_note_document_id uuid not null references public.delivery_note(document_id) on delete cascade,
    primary key(invoice_document_id, delivery_note_document_id),

    created_by uuid        not null references public.user(id) on delete restrict,
    created_at timestamptz not null default now()
);

comment on column public.delivery_note.updated_at is 'User who linked invoice and delivery-note';
comment on column public.delivery_note.created_at is 'Creation time of object.';

grant select on table public.invoice_delivery_note to domonda_user;

create index invoice_delivery_note_invoice_id_idx       on public.invoice_delivery_note (invoice_document_id);
create index invoice_delivery_note_delivery_note_id_idx on public.invoice_delivery_note (delivery_note_document_id);

----

create function public.invoice_find_delivery_notes(
  invoice public.invoice
) returns setof public.delivery_note as $$
  select delivery_note.*
  from public.delivery_note
    inner join public.document on document.id = invoice.document_id
    inner join public.document as delivery_note_document on delivery_note_document.id = delivery_note.document_id
  -- from the same client
  where document.client_company_id = delivery_note_document.client_company_id
  -- delivery note has a ready-like status
  and public.document_state(delivery_note_document) in ('READY', 'BOOKED', 'BOOKING_CANCELED', 'READY_FOR_BOOKING')
  -- date difference between invoice and delivery note is not more than 4 weeks
  and abs(invoice.invoice_date - delivery_note.issue_date) <= 28
  and (
    -- invoice's number is the delivery note invoice number
    (invoice.invoice_number is not null
      and invoice.invoice_number = delivery_note.invoice_number)
    -- invoice's delivery note numbers includes the delivery note number
    or (invoice.delivery_note_numbers is not null
      and delivery_note.note_number::text = any(invoice.delivery_note_numbers))
    -- invoice's delivery note numbers appear in the fulltext of the delivery note
    or (invoice.delivery_note_numbers is not null
      and exists (select
        from unnest(invoice.delivery_note_numbers) as delivery_note_number
        where delivery_note_document.fulltext ilike '%' || delivery_note_number || '%'))
  )
$$ language sql stable strict;

create function public.delivery_note_find_invoices(
  delivery_note public.delivery_note
) returns setof public.invoice as $$
  select invoice.*
  from public.invoice
    inner join public.document on document.id = delivery_note.document_id
    inner join public.document as invoice_document on invoice_document.id = invoice.document_id
  -- from the same client
  where document.client_company_id = invoice_document.client_company_id
  -- date difference between invoice and delivery note is not more than 4 days
  and abs(invoice.invoice_date - delivery_note.issue_date) <= 4
  and (
    -- delivery note invoice number is the invoice's number
    (delivery_note.invoice_number is not null
      and delivery_note.invoice_number = invoice.invoice_number)
    -- delivery note number is included in invoice's delivery note numbers
    or (delivery_note.note_number is not null
      and delivery_note.note_number::text = any(invoice.delivery_note_numbers))
    -- invoice's delivery note numbers appear in the fulltext of the delivery note
    or (invoice.delivery_note_numbers is not null
      and exists (select
        from unnest(invoice.delivery_note_numbers) as delivery_note_number
        where document.fulltext ilike '%' || delivery_note_number || '%'))
  )
$$ language sql stable strict;
