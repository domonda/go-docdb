create table public.invoice_accounting_item_cost_unit (
    id uuid primary key default uuid_generate_v4(),

    invoice_accounting_item_id  uuid not null references public.invoice_accounting_item(id) on delete cascade,
    client_company_cost_unit_id uuid not null references public.client_company_cost_unit(id) on delete cascade,
    unique(invoice_accounting_item_id, client_company_cost_unit_id),

    amount float8 not null check(amount >= 0), -- must be positive

    updated_at updated_time not null,
    created_at created_time not null
);

create index invoice_accounting_item_cost_unit_invoice_accounting_item_id_idx
    on public.invoice_accounting_item_cost_unit (invoice_accounting_item_id);
create index invoice_accounting_item_cost_unit_client_company_cost_unit_id_idx
    on public.invoice_accounting_item_cost_unit (client_company_cost_unit_id);

grant all on table public.invoice_accounting_item_cost_unit to domonda_user;
grant select on public.invoice_accounting_item_cost_unit to domonda_wg_user;

----

create function public.add_invoice_accounting_item_cost_unit(
    invoice_accounting_item_id  uuid,
    client_company_cost_unit_id uuid,
    amount                      float8
) returns public.invoice_accounting_item_cost_unit as
$$
    insert into public.invoice_accounting_item_cost_unit (
        invoice_accounting_item_id,
        client_company_cost_unit_id,
        amount
    ) values (
        add_invoice_accounting_item_cost_unit.invoice_accounting_item_id,
        add_invoice_accounting_item_cost_unit.client_company_cost_unit_id,
        add_invoice_accounting_item_cost_unit.amount
    )
    returning *
$$
language sql volatile;

create function public.update_invoice_accounting_item_cost_unit(
    id                          uuid,
    client_company_cost_unit_id uuid,
    amount                      float8
) returns public.invoice_accounting_item_cost_unit as
$$
    update public.invoice_accounting_item_cost_unit
    set
        client_company_cost_unit_id=update_invoice_accounting_item_cost_unit.client_company_cost_unit_id,
        amount=update_invoice_accounting_item_cost_unit.amount,
        updated_at=now()
    where id = update_invoice_accounting_item_cost_unit.id
    returning *
$$
language sql volatile;

create function public.delete_invoice_accounting_item_cost_unit(
    id uuid
) returns public.invoice_accounting_item_cost_unit as
$$
    delete from public.invoice_accounting_item_cost_unit
    where id = delete_invoice_accounting_item_cost_unit.id
    returning *
$$
language sql volatile;

----

create function public.invoice_accounting_item_cost_units_remaining_amount(
    invoice_accounting_item public.invoice_accounting_item
) returns float8 as
$$
    select coalesce(
        (
            round(public.invoice_accounting_item_net(invoice_accounting_item)::numeric, 2) - (
                select
                    -- we round intentionally to guarantee equality
                    round(sum(iaicc.amount)::numeric, 2)
                from public.invoice_accounting_item_cost_unit as iaicc
                where iaicc.invoice_accounting_item_id = invoice_accounting_item.id
            )
        ),
        round(public.invoice_accounting_item_net(invoice_accounting_item)::numeric, 2)
    )::float8
$$
language sql stable;

comment on function public.invoice_accounting_item_cost_units_remaining_amount is E'@notNull\nCalculates the difference between the summed amounts of the `InvoiceAccountingItemCostUnit`s and this `InvoiceAccountingItem` amount.';

----

create function public.invoice_accounting_item_cost_units_remaining_amount_is_zero(
    invoice_accounting_item public.invoice_accounting_item
) returns boolean as
$$
    select public.invoice_accounting_item_cost_units_remaining_amount(invoice_accounting_item) = 0
$$
language sql stable;

comment on function public.invoice_accounting_item_cost_units_remaining_amount_is_zero is E'@notNull\nChecks if the difference between the summed amounts of the `InvoiceAccountingItemCostUnit`s and this `InvoiceAccountingItem` amount is *zero*.';

----

create function public.invoice_accounting_item_cost_units_remaining_amount_is_ok(
    invoice_accounting_item public.invoice_accounting_item
) returns boolean as
$$
    select (
        public.invoice_accounting_item_cost_units_remaining_amount(invoice_accounting_item) = 0
    ) or (
        public.invoice_accounting_item_cost_units_remaining_amount(invoice_accounting_item) = round(public.invoice_accounting_item_net(invoice_accounting_item)::numeric, 2)
    )
$$
language sql stable;

comment on function public.invoice_accounting_item_cost_units_remaining_amount_is_ok is E'@notNull\nChecks if the difference between the summed amounts of the `InvoiceAccountingItemCostUnit`s and this `InvoiceAccountingItem` amount is *zero* or *equal*. Its OK for *equal* amounts because the booking is still not done and thats OK.';

----

create function public.invoice_accounting_items_cost_units_total_count(
  invoice public.invoice
) returns int as $$
  select count(1)::int
  from public.invoice_accounting_item
    inner join public.invoice_accounting_item_cost_unit
        on invoice_accounting_item_cost_unit.invoice_accounting_item_id = invoice_accounting_item.id
  where invoice_accounting_item.invoice_document_id = invoice.document_id
$$ language sql stable strict;
comment on function public.invoice_accounting_items_cost_units_total_count is '@notNull';
