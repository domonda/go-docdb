create table private.bludelta2_invoice_extraction (
    id serial primary key,

    document_id uuid not null,
    result jsonb not null,

    created_at timestamptz not null default now()
);

create index on private.bludelta2_invoice_extraction (document_id);
create index on private.bludelta2_invoice_extraction (created_at);
