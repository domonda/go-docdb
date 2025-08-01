create type api.money_transaction_type as enum (
    'INCOMING',
    'OUTGOING'
);

comment on type api.money_transaction_type is 'Type of a `MoneyTransaction`.';

----

create view api.money_transaction with (security_barrier) as
    select
        mt.id,
        mt.account_id,
        mt.type::text::api.money_transaction_type,
        mt.partner_name,
        mt.partner_iban,
        mt.partner_company_id,
        mt.amount,
        mt.foreign_currency,
        mt.foreign_amount,
        mt.purpose,
        mt.booking_date,
        mt.value_date,
        mt.import_document_id,
        mt.money_category_id,
        mt.updated_at,
        mt.created_at
    from public.money_transaction as mt
        inner join api.money_account as ma on (ma.id = mt.account_id);

grant select on table api.money_transaction to domonda_api;

comment on column api.money_transaction.account_id is '@notNull';
comment on column api.money_transaction.type is '@notNull';
comment on column api.money_transaction.amount is '@notNull';
comment on column api.money_transaction.booking_date is '@notNull';
comment on column api.money_transaction.updated_at is '@notNull';
comment on column api.money_transaction.created_at is '@notNull';
comment on view api.money_transaction is $$
@primaryKey id
@foreignKey (account_id) references api.money_account(id)
@foreignKey (partner_company_id) references api.partner_company(id)
@foreignKey (import_document_id) references api.document(id)
A `MoneyTransaction` is a money related turnover belonging to a `MoneyAccount`.$$;
