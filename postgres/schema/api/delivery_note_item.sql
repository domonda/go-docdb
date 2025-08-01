create view api.delivery_note_item with (security_barrier) as
    select
        it.id,
        it.delivery_note_document_id,
        it.pos_no,
        it.title,
        it.product_no,
        it.ean_no,
        it.gtin_no,
        it.quantity,
        it.quantity_unit,
        it.weight,
        it.weight_unit,
        it.updated_at,
        it.created_at
    from public.delivery_note_item as it
        inner join api.delivery_note as dn on (dn.document_id = it.delivery_note_document_id);

grant select on table api.delivery_note_item to domonda_api;

comment on column api.delivery_note_item.delivery_note_document_id is '@notNull';
comment on column api.delivery_note_item.pos_no is '@notNull';
comment on column api.delivery_note_item.title is '@notNull';
comment on column api.delivery_note_item.quantity is '@notNull';
comment on view api.delivery_note_item is $$
@primaryKey id
@foreignKey (delivery_note_document_id) references api.delivery_note (document_id)$$;
