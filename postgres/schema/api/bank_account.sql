create view api.bank_account with (security_barrier) as 
    select
        ba.id,
        ba.client_company_id,
        ba.bank_bic::text,
        ba.iban,
        ba.account_number,
        ba.type,
        ba.name,
        ba.holder,
        ba.description,
        ba.currency,
        ba.available,
        ba.limit,
        ba.balance,
        ba.general_ledger_account_id,
        ba.xs2a_account_id,
        ba.active,
        ba.include_holder_with_payment,
        ba.updated_at::updated_time,
        ba.created_at::created_time
    from public.bank_account as ba
        inner join api.client_company as cc on (cc.company_id = ba.client_company_id);

grant select on table api.bank_account to domonda_api;

comment on column api.bank_account.client_company_id is '@notNull';
comment on column api.bank_account.bank_bic is '@notNull';
comment on column api.bank_account.iban is '@notNull';
comment on column api.bank_account.type is '@notNull';
comment on column api.bank_account.holder is '@notNull';
comment on column api.bank_account.currency is '@notNull';
comment on column api.bank_account.active is '@notNull';
comment on column api.bank_account.include_holder_with_payment is '@notNull';
comment on view api.bank_account is $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
@foreignKey (general_ledger_account_id) references api.general_ledger_account (id)$$;
