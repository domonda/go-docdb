create view api.invoice_delivery_note with (security_barrier) as
    select
        invoice_delivery_note.invoice_document_id,
        invoice_delivery_note.delivery_note_document_id,
        invoice_delivery_note.created_by,
        invoice_delivery_note.created_at
    from public.invoice_delivery_note
        inner join api.document as inv on inv.id = invoice_delivery_note.invoice_document_id
        inner join api.document as del on del.id = invoice_delivery_note.delivery_note_document_id
    ;

grant select on table api.invoice_delivery_note to domonda_api;

comment on column api.invoice_delivery_note.invoice_document_id is '@notNull';
comment on column api.invoice_delivery_note.delivery_note_document_id is '@notNull';
comment on column api.invoice_delivery_note.created_by is '@notNull';
comment on column api.invoice_delivery_note.created_at is '@notNull';
comment on view api.invoice_delivery_note is $$
@primaryKey invoice_document_id,delivery_note_document_id
@foreignKey (invoice_document_id) references api.invoice (document_id)
@foreignKey (delivery_note_document_id) references api.delivery_note (document_id)$$;
