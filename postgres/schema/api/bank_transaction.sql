create view api.bank_transaction with (security_barrier) as 
    select
        bt.id,
        bt.account_id,
        bt.partner_name,
        bt.partner_iban,
        bt.partner_bic,
        bt.partner_company_id,
        bt.type,
        bt.fee,
        bt.tax,
        bt.amount,
        bt.foreign_currency,
        bt.foreign_amount,
        bt.reference,
        bt.booking_date,
        bt.value_date,
        bt.tags,
        bt.import_document_id,
        bt.money_category_id,
        bt.updated_at::updated_time,
        bt.created_at::created_time
    from public.bank_transaction as bt
        inner join api.bank_account as ba on (ba.id = bt.account_id);

grant select on table api.bank_transaction to domonda_api;

comment on column api.bank_transaction.account_id is '@notNull';
comment on column api.bank_transaction."type" is '@notNull';
comment on column api.bank_transaction.amount is '@notNull';
comment on column api.bank_transaction.booking_date is '@notNull';
comment on view api.bank_transaction is $$
@primaryKey id
@foreignKey (account_id) references api.bank_account (id)
@foreignKey (partner_company_id) references api.partner_company (id)
@foreignKey (import_document_id) references api.document (id)$$;
