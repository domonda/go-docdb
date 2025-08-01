create view api.client_company_cost_center with (security_barrier) as
    select 
        ccc.id,
        ccc.client_company_id,
        ccc.number,
        ccc.description,
        ccc.historic,
        ccc.currency,
        ccc.updated_at,
        ccc.created_at
    from public.client_company_cost_center as ccc
        inner join api.client_company as cc on (cc.company_id = ccc.client_company_id);

grant select on table api.client_company_cost_center to domonda_api;

comment on column api.client_company_cost_center.client_company_id is '@notNull';
comment on column api.client_company_cost_center.number is '@notNull';
comment on column api.client_company_cost_center.description is '@notNull';
comment on column api.client_company_cost_center.currency is '@notNull';
comment on view api.client_company_cost_center is $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
A `ClientCompanyCostCenter` represents a cost center which is linked to a `ClientCompany`.$$;
