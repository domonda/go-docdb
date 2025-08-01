create table public.invoice_item (
    id uuid primary key default uuid_generate_v4(),

    invoice_document_id uuid references public.invoice(document_id) on delete cascade,
    pos_no              trimmed_text not null collate "numeric",
    unique(invoice_document_id, pos_no),

    title            trimmed_text,
    description      trimmed_text,
    order_no         trimmed_text,
    delivery_no      trimmed_text,
    product_no       trimmed_text,
    ean_no           trimmed_text,
    gtin_no          trimmed_text,
    quantity         float8 check(quantity >= 0),
    unit             trimmed_text,
    unit_net_price   float8,
    total_price      float8,
    discount_percent float8 check(discount_percent >= 0 and discount_percent <= 100),
    vat_name         trimmed_text,
    vat_percent      float8 check(vat_percent >= 0 and vat_percent < 100),

    source     text not null default 'UNKNOWN',
    updated_at updated_time not null,
    created_at created_time not null
);

comment on column public.invoice_item.updated_at is 'Time of last update.';
comment on column public.invoice_item.created_at is 'Creation time of object.';

grant all on table public.invoice_item to domonda_user;

----

create function public.invoice_item_net_amount(
    item public.invoice_item
) returns float8 as
$$
    select
        item.quantity *
        item.unit_net_price *
        (100 - item.discount_percent) / 100
$$
language sql stable strict;

comment on function public.invoice_item_net_amount is 'Net amount of the invoice item with optional discount';

----

create function public.delete_invoice_item(
    id uuid
) returns public.invoice_item as
$$
    delete from public.invoice_item
        where id = delete_invoice_item.id
    returning *
$$
language sql volatile strict;
