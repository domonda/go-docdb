create view api.invoice_item with (security_barrier) as
    select
        ii.id,
        ii.invoice_document_id,
        ii.pos_no,
        ii.title,
        ii.description,
        ii.order_no,
        ii.delivery_no,
        ii.product_no,
        ii.ean_no,
        ii.gtin_no,
        ii.quantity,
        ii.unit,
        ii.unit_net_price,
        ii.total_price,
        ii.discount_percent,
        ii.vat_name,
        ii.vat_percent,
        ii.updated_at,
        ii.created_at
    from public.invoice_item as ii
        join api.invoice as i on i.document_id = ii.invoice_document_id;

grant select, insert, delete, update on table api.invoice_item TO domonda_api;

comment on column api.invoice_item.pos_no is '@notNull';
comment on view api.invoice_item is $$
@primaryKey id
@foreignKey (invoice_document_id) references api.invoice (document_id)
A `InvoiceItem` represents a single line item belonging to an `Invoice`.$$;
