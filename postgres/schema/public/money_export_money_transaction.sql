create table public.money_export_money_transaction (
    id uuid primary key default uuid_generate_v4(),

    money_export_id uuid not null references public.money_export(id) on delete cascade,

    money_account     public.money_account not null,
    money_transaction public.money_transaction not null,

    bank_transaction        public.bank_transaction,
    credit_card_transaction public.credit_card_transaction,
    cash_transaction        public.cash_transaction,
    paypal_transaction      public.paypal_transaction,
    stripe_transaction      public.stripe_transaction
);

grant select, insert on table public.money_export_money_transaction to domonda_user;

comment on table public.money_export_money_transaction is 'The transaction that belongs to a money export';

----

create table public.money_export_money_transaction_document (
    money_export_money_transaction_id uuid not null references public.money_export_money_transaction(id) on delete cascade,
    document_id                       uuid not null references public.document(id) on delete cascade,
    primary key(money_export_money_transaction_id, document_id),

    document_version timestamptz not null,

    document_money_transaction public.document_money_transaction not null,

    document_bank_transaction        public.document_bank_transaction,
    document_credit_card_transaction public.document_credit_card_transaction,
    document_cash_transaction        public.document_cash_transaction,
    document_paypal_transaction      public.document_paypal_transaction,
    document_stripe_transaction      public.document_stripe_transaction
);

grant select, insert on table public.money_export_money_transaction_document to domonda_user;

comment on table public.money_export_money_transaction_document is 'The matched document of the transaction that belongs to a money export';
