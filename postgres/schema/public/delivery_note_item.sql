-- n:n relations between invoices and delivery notes are kept in public.invoice_delivery_note,
-- so fare there is no relation between delivery note items and invoice items
create table public.delivery_note_item (
    id uuid primary key default uuid_generate_v4(),

    delivery_note_document_id uuid not null references public.delivery_note(document_id) on delete cascade,
    pos_no                    trimmed_text not null,
    unique(delivery_note_document_id, pos_no),

    title         trimmed_text not null,
    product_no    trimmed_text,
    ean_no        trimmed_text,
    gtin_no       trimmed_text,
    quantity      float8 not null check(quantity >= 0.0),
    quantity_unit trimmed_text,
    "weight"      float8 check("weight" >= 0.0),
    weight_unit   trimmed_text,

    updated_at updated_time not null,
    created_at created_time not null
);

comment on column public.delivery_note_item.updated_at is 'Time of last update.';
comment on column public.delivery_note_item.created_at is 'Creation time of object.';

grant select, update on table public.delivery_note_item to domonda_user;
