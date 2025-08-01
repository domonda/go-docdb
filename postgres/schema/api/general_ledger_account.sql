create view api.general_ledger_account with (security_barrier) as
    select 
        gla.id,
        gla.number,
        gla.currency,
        gla.name,
        gla.category,
        gla.updated_at,
        gla.created_at
    from public.general_ledger_account as gla
        inner join api.client_company as cc on cc.company_id = gla.client_company_id;

grant select on table api.general_ledger_account to domonda_api;

comment on column api.general_ledger_account.number is '@notNull';
comment on column api.general_ledger_account.updated_at is '@notNull';
comment on column api.general_ledger_account.created_at is '@notNull';
comment on view api.general_ledger_account is $$
@primaryKey id
$$;
