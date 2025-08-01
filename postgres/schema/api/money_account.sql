create view api.money_account with (security_barrier) as 
    select
        ma.id,
        ma.client_company_id,
        ma.type,
        ma.name,
        ma.external_id,
        ma.currency,
        ma.balance,
        ma.active,
        ma.updated_at,
        ma.created_at
    from public.money_account as ma
        inner join api.client_company as cc on (cc.company_id = ma.client_company_id);

grant select on table api.money_account to domonda_api;

comment on column api.money_account.id is '@notNull';
comment on column api.money_account.client_company_id is '@notNull';
comment on column api.money_account.type is '@notNull';
comment on column api.money_account.name is '@notNull';
comment on column api.money_account.external_id is '@notNull';
comment on column api.money_account.currency is '@notNull';
comment on column api.money_account.updated_at is '@notNull';
comment on column api.money_account.created_at is '@notNull';
comment on view api.money_account is $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
A `MoneyAccount` belonging to a `ClientCompany`. It holds any form of money related accounts (bank, credit-card, PayPal, etc.).$$;
