create table private.docvibe_invoice_extraction (
    id serial primary key,

    endpoint text not null default '/domonda/extract/accounting-invoice',
    document_id uuid not null,
    request_id  text not null,

    result jsonb not null,

    created_at timestamptz not null default now()
);

create index on private.docvibe_invoice_extraction (document_id);
create index on private.docvibe_invoice_extraction (request_id);
create index on private.docvibe_invoice_extraction (created_at);
