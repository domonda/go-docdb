create type abacus.booking_category as enum (
	'ER', -- Incoming Invoice
	'AR', -- Outgoing Invoice
	'BK', -- Bank Transaction
	'KA', -- Cash Transaction
	'KK', -- Credit Card Transaction
	'VK'  -- Settlement Account Transaction
);

create table abacus.booking_type (
	id                   uuid primary key,
    document_category_id uuid references public.document_category(id) on delete set null,

    client_id            uuid not null references abacus.client(id) on delete cascade,
	booking_category     abacus.booking_category not null,
    booking_name         text not null,
    unique(client_id, booking_category, booking_name),

    verbose_name   text,
    account_number text,-- can only be specified for booking_category = bk, ka, kk, vk

    updated_at updated_time not null,
    created_at created_time not null
);

create index abacus_booking_type_document_category_id_idx on abacus.booking_type(document_category_id);