-- n:n relations between invoices and delivery notes are kept in public.invoice_delivery_note
create table public.delivery_note (
    document_id uuid primary key references public.document(id) on delete cascade,

    partner_company_id              uuid references public.partner_company(id),
    partner_company_id_confirmed_by trimmed_text,
    partner_company_id_confirmed_at timestamptz,

    partner_company_location_id              uuid references public.company_location(id),
    partner_company_location_id_confirmed_by trimmed_text,
    partner_company_location_id_confirmed_at timestamptz,
    constraint partner_company_location_check
        check(partner_company_location_id is null or partner_company_id is not null),

    note_number              trimmed_text,
    note_number_confirmed_by trimmed_text,
    note_number_confirmed_at timestamptz,

    invoice_number              trimmed_text,
    invoice_number_confirmed_by trimmed_text,
    invoice_number_confirmed_at timestamptz,

    issue_date              date,
    issue_date_confirmed_by trimmed_text,
    issue_date_confirmed_at timestamptz,

    delivered_at              timestamptz,
    delivered_at_confirmed_by trimmed_text,
    delivered_at_confirmed_at timestamptz,

    net_sum              float8,
    net_sum_confirmed_by text,
    net_sum_confirmed_at timestamptz,
    constraint positive_net_check check(net_sum >= 0),

    updated_at updated_time not null,
    created_at created_time not null
);

comment on column public.delivery_note.updated_at is 'Time of last update.';
comment on column public.delivery_note.created_at is 'Creation time of object.';

grant select, update on table public.delivery_note to domonda_user;

create index delivery_note_partner_company_id_idx on public.delivery_note (partner_company_id);
create index delivery_note_partner_company_location_id_idx on public.delivery_note (partner_company_location_id);
create index delivery_note_note_number_idx on public.delivery_note (note_number);
create index delivery_note_invoice_number_idx on public.delivery_note (invoice_number);
create index delivery_note_issue_date_idx on public.delivery_note (issue_date);
