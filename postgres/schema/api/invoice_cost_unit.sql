create view api.invoice_cost_unit with (security_barrier) as
    select
        icu.id,
        icu.invoice_document_id,
        icu.client_company_cost_unit_id,
        icu.amount,
        icu.updated_at,
        icu.created_at
    from public.invoice_cost_unit as icu
        join api.invoice as i on i.document_id = icu.invoice_document_id;

grant select on table api.invoice_cost_unit to domonda_api;

comment on column api.invoice_cost_unit.invoice_document_id is '@notNull';
comment on column api.invoice_cost_unit.client_company_cost_unit_id is '@notNull';
comment on column api.invoice_cost_unit.amount is '@notNull';
comment on view api.invoice_cost_unit is $$
@primaryKey id
@foreignKey (invoice_document_id) references api.invoice (document_id)
@foreignKey (client_company_cost_unit_id) references api.client_company_cost_unit (id)
`InvoiceCostUnit` books a `ClientCompanyCostUnit` amount for an `Invoice`.$$;