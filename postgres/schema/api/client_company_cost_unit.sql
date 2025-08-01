create view api.client_company_cost_unit with (security_barrier) as
    select
        ccc.id,
        ccc.client_company_id,
        ccc.number,
        ccc.description,
        ccc.historic,
        ccc.currency,
        ccc.updated_at,
        ccc.created_at
    from public.client_company_cost_unit as ccc
        inner join api.client_company as cc on (cc.company_id = ccc.client_company_id);

grant select on table api.client_company_cost_unit to domonda_api;

comment on column api.client_company_cost_unit.client_company_id is '@notNull';
comment on column api.client_company_cost_unit.number is '@notNull';
comment on column api.client_company_cost_unit.description is '@notNull';
comment on column api.client_company_cost_unit.currency is '@notNull';
comment on view api.client_company_cost_unit is $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
A `ClientCompanyCostUnit` represents a cost unit which is linked to a `ClientCompany`.$$;
