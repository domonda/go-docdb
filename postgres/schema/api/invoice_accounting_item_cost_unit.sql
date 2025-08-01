create view api.invoice_accounting_item_cost_unit with (security_barrier) as
    select
        icu.id,
        icu.invoice_accounting_item_id,
        icu.client_company_cost_unit_id,
        ccu.number,
        ccu.description,
        ccu.currency,
        icu.amount,
        icu.updated_at,
        icu.created_at
    from public.invoice_accounting_item_cost_unit as icu
        join api.invoice_accounting_item as iai on iai.id = icu.invoice_accounting_item_id
        join api.client_company_cost_unit as ccu on ccu.id = icu.client_company_cost_unit_id;

grant select on table api.invoice_accounting_item_cost_unit to domonda_api;

comment on column api.invoice_accounting_item_cost_unit.invoice_accounting_item_id is '@notNull';
comment on column api.invoice_accounting_item_cost_unit.client_company_cost_unit_id is '@notNull';
comment on column api.invoice_accounting_item_cost_unit.number is '@notNull';
comment on column api.invoice_accounting_item_cost_unit.description is '@notNull';
comment on column api.invoice_accounting_item_cost_unit.currency is '@notNull';
comment on column api.invoice_accounting_item_cost_unit.amount is '@notNull';
comment on view api.invoice_accounting_item_cost_unit is $$
@primaryKey id
@foreignKey (invoice_accounting_item_id) references api.invoice_accounting_item (id)
@foreignKey (client_company_cost_unit_id) references api.client_company_cost_unit (id)
`InvoiceAccountingItemCostUnit` books a `ClientCompanyCostUnit` amount for an `InvoiceAccountingItem`.$$;
