create view api.invoice_cost_center with (security_barrier) as
    select
        icc.id,
        icc.document_id as invoice_document_id,
        icc.client_company_cost_center_id,
        icc.amount,
        icc.page,
        icc.pos_x,
        icc.pos_y,
        icc.updated_at,
        icc.created_at
    from public.invoice_cost_center as icc
        join api.invoice as i on i.document_id = icc.document_id;

grant select on table api.invoice_cost_center to domonda_api;

comment on column api.invoice_cost_center.invoice_document_id is '@notNull';
comment on column api.invoice_cost_center.client_company_cost_center_id is '@notNull';
comment on column api.invoice_cost_center.amount is '@notNull';
comment on view api.invoice_cost_center is $$
@primaryKey id
@foreignKey (invoice_document_id) references api.invoice (document_id)
@foreignKey (client_company_cost_center_id) references api.client_company_cost_center (id)
`InvoiceCostCenter` books a `ClientCompanyCostCenter` amount for an `Invoice`.$$;