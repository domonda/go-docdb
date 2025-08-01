create table public.invoice_cost_center (
    id uuid primary key default uuid_generate_v4(),

    document_id                   uuid not null references public.invoice(document_id) on delete cascade,
    client_company_cost_center_id uuid not null references public.client_company_cost_center(id) on delete cascade,
    -- unique index invoice_cost_center_unique_cost_center_id

    amount float8 not null,

    -- position on document (optional)
    page  int,
    pos_x float8,
    pos_y float8,

    updated_at updated_time not null,
    created_at created_time not null
);

create unique index invoice_cost_center_unique_cost_center_id
    on public.invoice_cost_center (document_id, client_company_cost_center_id);
create index invoice_cost_center_document_id_idx
    on public.invoice_cost_center (document_id);
create index invoice_cost_center_client_company_cost_center_id_idx
    on public.invoice_cost_center (client_company_cost_center_id);

grant select, insert, update, delete on table public.invoice_cost_center to domonda_user;
grant select on public.invoice_cost_center to domonda_wg_user;

----

create function public.add_invoice_cost_center(
    document_id                   uuid,
    client_company_cost_center_id uuid,
    amount                        float8,
    -- position on document (optional)
    page  int = null,
    pos_x float8 = null,
    pos_y float8 = null
) returns public.invoice_cost_center as
$$
    insert into
        public.invoice_cost_center (
            id,
            document_id,
            client_company_cost_center_id,
            amount,
            page,
            pos_x,
            pos_y
        )
        values (
            uuid_generate_v4(),
            add_invoice_cost_center.document_id,
            add_invoice_cost_center.client_company_cost_center_id,
            add_invoice_cost_center.amount,
            add_invoice_cost_center.page,
            add_invoice_cost_center.pos_x,
            add_invoice_cost_center.pos_y
        )
        returning *
$$
language sql volatile;

comment on function public.add_invoice_cost_center(uuid, uuid, float8, int, float8, float8) is 'Adds an amount from an invoice to a cost center, with optional positioning on the document';
grant execute on function public.add_invoice_cost_center(uuid, uuid, float8, int, float8, float8) to domonda_user;

----

create function public.update_invoice_cost_center(
    id                            uuid,
    client_company_cost_center_id uuid,
    amount                        float8,
    -- position on document (optional)
    page  int = null,
    pos_x float8 = null,
    pos_y float8 = null
) returns public.invoice_cost_center as
$$
    update public.invoice_cost_center
        set
            client_company_cost_center_id = update_invoice_cost_center.client_company_cost_center_id,
            amount = update_invoice_cost_center.amount,
            page = update_invoice_cost_center.page,
            pos_x = update_invoice_cost_center.pos_x,
            pos_y = update_invoice_cost_center.pos_y,
            updated_at = now()
        where id = update_invoice_cost_center.id
        returning *
$$
language sql volatile;

comment on function public.update_invoice_cost_center(uuid, uuid, float8, int, float8, float8) is 'Updates an invoice to cost-center mapping, with optional positioning on the document';

grant execute on function public.update_invoice_cost_center(uuid, uuid, float8, int, float8, float8) to domonda_user;

----

create function public.remove_invoice_cost_center(
    id uuid
) returns public.invoice_cost_center as
$$
    delete from public.invoice_cost_center
        where id = remove_invoice_cost_center.id
        returning *
$$
language sql volatile;

comment on function public.remove_invoice_cost_center(uuid) is 'Removes a cost-center mapping from an invoice';

grant execute on function public.remove_invoice_cost_center(uuid) to domonda_user;
