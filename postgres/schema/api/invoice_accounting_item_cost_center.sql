create view api.invoice_accounting_item_cost_center with (security_barrier) as
    select
        icc.id,
        icc.invoice_accounting_item_id,
        icc.client_company_cost_center_id,
        ccc.number,
        ccc.description,
        ccc.currency,
        icc.amount,
        icc.updated_at,
        icc.created_at
    from public.invoice_accounting_item_cost_center as icc
        join api.invoice_accounting_item as iai on iai.id = icc.invoice_accounting_item_id
        join api.client_company_cost_center as ccc on ccc.id = icc.client_company_cost_center_id;

grant select on table api.invoice_accounting_item_cost_center to domonda_api;

comment on column api.invoice_accounting_item_cost_center.invoice_accounting_item_id is '@notNull';
comment on column api.invoice_accounting_item_cost_center.client_company_cost_center_id is '@notNull';
comment on column api.invoice_accounting_item_cost_center.number is '@notNull';
comment on column api.invoice_accounting_item_cost_center.description is '@notNull';
comment on column api.invoice_accounting_item_cost_center.currency is '@notNull';
comment on column api.invoice_accounting_item_cost_center.amount is '@notNull';
comment on view api.invoice_accounting_item_cost_center is $$
@primaryKey id
@foreignKey (invoice_accounting_item_id) references api.invoice_accounting_item (id)
@foreignKey (client_company_cost_center_id) references api.client_company_cost_center (id)
`InvoiceAccountingItemCostCenter` books a `ClientCompanyCostCenter` amount for an `InvoiceAccountingItem`.$$;
