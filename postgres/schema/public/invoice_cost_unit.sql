create table public.invoice_cost_unit (
    id uuid primary key default uuid_generate_v4(),

    invoice_document_id         uuid not null references public.invoice(document_id) on delete cascade,
    client_company_cost_unit_id uuid not null references public.client_company_cost_unit(id) on delete cascade,

    amount float8 not null,

    updated_at updated_time not null,
    created_at created_time not null
);

create unique index invoice_cost_unit_unique_cost_unit_id
    on public.invoice_cost_unit (invoice_document_id, client_company_cost_unit_id);
create index invoice_cost_unit_invoice_document_id_idx
    on public.invoice_cost_unit (invoice_document_id);
create index invoice_cost_unit_client_company_cost_unit_id_idx
    on public.invoice_cost_unit (client_company_cost_unit_id);

grant select, insert, update, delete on table public.invoice_cost_unit to domonda_user;
grant select on public.invoice_cost_unit to domonda_wg_user;

----

create function public.add_invoice_cost_unit(
    invoice_document_id            uuid,
    client_company_cost_unit_id uuid,
    amount                         float8
) returns public.invoice_cost_unit as $$
    insert into public.invoice_cost_unit (invoice_document_id, client_company_cost_unit_id, amount)
    values (
        add_invoice_cost_unit.invoice_document_id,
        add_invoice_cost_unit.client_company_cost_unit_id,
        add_invoice_cost_unit.amount
    )
    returning *
$$ language sql volatile;

create function public.update_invoice_cost_unit(
    id                             uuid,
    client_company_cost_unit_id uuid,
    amount                         float8
) returns public.invoice_cost_unit as $$
    update public.invoice_cost_unit
        set
            client_company_cost_unit_id=update_invoice_cost_unit.client_company_cost_unit_id,
            amount=update_invoice_cost_unit.amount,
            updated_at=now()
    where id = update_invoice_cost_unit.id
    returning *
$$ language sql volatile;

create function public.remove_invoice_cost_unit(
    id uuid
) returns public.invoice_cost_unit as $$
    delete from public.invoice_cost_unit
    where id = remove_invoice_cost_unit.id
    returning *
$$ language sql volatile;
