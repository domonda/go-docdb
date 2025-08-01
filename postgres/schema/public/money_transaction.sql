-- public.money_transaction (
    -- id                 uuid NOT NULL,
    -- account_id         uuid NOT NULL REFERENCES public.money_transaction(id),
    -- type               public.money_transaction_type NOT NULL,
    -- partner_name       non_empty_text,
    -- partner_iban       bank_iban,
    -- partner_company_id uuid REFERENCES public.partner_company(id),
    -- amount             float8 NOT NULL,
    -- foreign_currency   currency_code,
    -- foreign_amount     float8,
    -- purpose            text,
    -- booking_date       date NOT NULL,
    -- value_date         date,
    -- import_document_id uuid REFERENCES public.document(id) ON DELETE CASCADE,
    -- money_category_id  uuid REFERENCES public.money_category(id) ON DELETE RESTRICT,
    -- note               non_empty_text,
    -- updated_at         updated_time NOT NULL,
    -- created_at         created_time NOT NULL
-- )

create function private.money_transaction_purpose_delimiter() returns text as
$$
    select '; '
$$
language sql immutable;

create type public.money_transaction_type as enum (
    'INCOMING',
    'OUTGOING'
);

comment on type public.money_transaction_type is 'Type of the `MoneyTransaction`.';

create view public.money_transaction as
    (
        select
            bank_transaction.id,
            bank_transaction.account_id,
            bank_transaction."type"::text::public.money_transaction_type,
            bank_transaction.partner_name,
            bank_transaction.partner_iban,
            bank_transaction.partner_company_id,
            bank_transaction.amount,
            bank_transaction.foreign_currency,
            bank_transaction.foreign_amount,
            array_to_string(bank_transaction.reference, private.money_transaction_purpose_delimiter()) as purpose,
            bank_transaction.booking_date,
            bank_transaction.value_date,
            bank_transaction.import_document_id,
            bank_transaction.money_category_id,
            bank_transaction.note,
            bank_transaction.updated_at,
            bank_transaction.created_at
        from public.bank_transaction
    ) union all (
        select
            credit_card_transaction.id,
            credit_card_transaction.account_id,
            credit_card_transaction."type"::text::public.money_transaction_type,
            credit_card_transaction.partner_name,
            null::bank_iban as partner_iban,
            credit_card_transaction.partner_company_id,
            credit_card_transaction.amount,
            credit_card_transaction.foreign_currency,
            credit_card_transaction.foreign_amount,
            array_to_string(credit_card_transaction.reference, private.money_transaction_purpose_delimiter()) as purpose,
            credit_card_transaction.booking_date,
            credit_card_transaction.value_date,
            credit_card_transaction.import_document_id,
            credit_card_transaction.money_category_id,
            credit_card_transaction.note,
            credit_card_transaction.updated_at,
            credit_card_transaction.created_at
        from public.credit_card_transaction
    ) union all (
        select
            cash_transaction.id,
            cash_transaction.account_id,
            cash_transaction."type"::text::public.money_transaction_type,
            cash_transaction.partner_name,
            null::bank_iban as partner_iban,
            cash_transaction.partner_company_id,
            cash_transaction.amount,
            null::currency_code as foreign_currency,
            null::float8 as foreign_amount,
            cash_transaction.purpose,
            cash_transaction.booking_date,
            null::date as value_date,
            cash_transaction.import_document_id,
            cash_transaction.money_category_id,
            cash_transaction.note,
            cash_transaction.updated_at,
            cash_transaction.created_at
        from public.cash_transaction
    );
    -- TODO-db-191205 add union for other transaction types

grant select on public.money_transaction TO domonda_user;
grant select on public.money_transaction to domonda_wg_user;

comment on column public.money_transaction.account_id IS '@notNull';
comment on column public.money_transaction."type" IS '@notNull';
comment on column public.money_transaction.amount IS '@notNull';
comment on column public.money_transaction.booking_date IS '@notNull';
comment on column public.money_transaction.updated_at IS '@notNull';
comment on column public.money_transaction.created_at IS '@notNull';
comment on view public.money_transaction IS $$
@primaryKey id
@foreignKey (account_id) references public.money_account (id)
@foreignKey (partner_company_id) references public.partner_company (id)
@foreignKey (import_document_id) references public.document (id)
@foreignKey (money_category_id) references public.money_category (id)
A `MoneyTransaction` belonging to a `MoneyAccount`. It abstracts over all supported forms of money related transactions (`BankTransaction`, `CreditCardTransaction`, `CashTransaction`, `PaypalTransaction` or `StripeTransaction`).$$;

----

-- TODO drop this view and add client_company_id column to public.money_transaction
create view public.money_transaction_account as
(
    select
        bank_transaction.id,
        bank_transaction.account_id,
        bank_transaction.type::text::public.money_transaction_type,
        bank_account.client_company_id
    from public.bank_transaction
        join public.bank_account on bank_account.id = bank_transaction.account_id
) union all (
    select
        credit_card_transaction.id,
        credit_card_transaction.account_id,
        credit_card_transaction.type::text::public.money_transaction_type,
        credit_card_account.client_company_id
    from public.credit_card_transaction
        join public.credit_card_account on credit_card_account.id = credit_card_transaction.account_id
) union all (
    select
        cash_transaction.id,
        cash_transaction.account_id,
        cash_transaction.type::text::public.money_transaction_type,
        cash_account.client_company_id
    from public.cash_transaction
        join public.cash_account on cash_account.id = cash_transaction.account_id
);

grant select on public.money_transaction_account to domonda_user;
grant select on public.money_transaction_account to domonda_wg_user;

comment on column public.money_transaction_account.account_id is '@notNull';
comment on column public.money_transaction_account.type is '@notNull';
comment on column public.money_transaction_account.client_company_id is '@notNull';
comment on view public.money_transaction_account is $$
@primaryKey id
@foreignKey (account_id) references public.money_account (id)
@foreignKey (client_company_id) references public.client_company (company_id)
Account data for money transations.$$;


----

create function public.money_transactions_by_ids(
    ids uuid[]
) returns setof public.money_transaction as
$$
    select * from public.money_transaction where (id = any(ids))
$$
language sql stable strict;

----

create function public.money_transaction_derived_partner_name(
    money_transaction public.money_transaction
) returns text as $$
    select coalesce(
        money_transaction.partner_name,
        (select partner_company.derived_name
        from public.partner_company
        where partner_company.id = money_transaction.partner_company_id)
    )
$$ language sql stable strict;

----

create function public.money_transaction_signed_amount(
    money_transaction public.money_transaction
) returns float8 as
$$
    select
        case money_transaction."type"
            when 'OUTGOING' then money_transaction.amount * -1
            else money_transaction.amount
        end
$$
language sql immutable;

comment on function public.money_transaction_signed_amount is '@notNull';

----

create function public.money_transaction_money_account_type (
    money_transaction public.money_transaction
) returns public.money_account_type as
$$
    select "type" from public.money_account where (id = money_transaction.account_id)
$$
language sql stable strict;

comment on function public.money_transaction_money_account_type is '@notNull';

----

create function public.money_transaction_bank_transaction_by_id (
    money_transaction public.money_transaction
) returns public.bank_transaction as
$$
    select * from public.bank_transaction where (id = money_transaction.id)
$$
language sql stable strict;

----

create function public.money_transaction_credit_card_transaction_by_id (
    money_transaction public.money_transaction
) returns public.credit_card_transaction as
$$
    select * from public.credit_card_transaction where (id = money_transaction.id)
$$
language sql stable strict;

----

create function public.money_transaction_cash_transaction_by_id (
    money_transaction public.money_transaction
) returns public.cash_transaction as
$$
    select * from public.cash_transaction where (id = money_transaction.id)
$$
language sql stable strict;

----

create function public.money_transaction_paypal_transaction_by_id (
    money_transaction public.money_transaction
) returns public.paypal_transaction as
$$
    select * from public.paypal_transaction where (id = money_transaction.id)
$$
language sql stable strict;

----

create function public.money_transaction_stripe_transaction_by_id (
    money_transaction public.money_transaction
) returns public.stripe_transaction as
$$
    select * from public.stripe_transaction where (id = money_transaction.id)
$$
language sql stable strict;

----

create function public.bank_transaction_money_transaction(
    bank_transaction public.bank_transaction
) returns public.money_transaction as $$
    select
        bank_transaction.id,
        bank_transaction.account_id,
        bank_transaction."type"::text::public.money_transaction_type,
        bank_transaction.partner_name,
        bank_transaction.partner_iban,
        bank_transaction.partner_company_id,
        bank_transaction.amount,
        bank_transaction.foreign_currency,
        bank_transaction.foreign_amount,
        array_to_string(bank_transaction.reference, private.money_transaction_purpose_delimiter()) as purpose,
        bank_transaction.booking_date,
        bank_transaction.value_date,
        bank_transaction.import_document_id,
        bank_transaction.money_category_id,
        bank_transaction.note,
        bank_transaction.updated_at,
        bank_transaction.created_at
$$ language sql immutable;

comment on function public.bank_transaction_money_transaction is '@notNull';

----

create function public.credit_card_transaction_money_transaction(
    credit_card_transaction public.credit_card_transaction
) returns public.money_transaction as $$
    select
        credit_card_transaction.id,
        credit_card_transaction.account_id,
        credit_card_transaction."type"::text::public.money_transaction_type,
        credit_card_transaction.partner_name,
        null::bank_iban as partner_iban,
        credit_card_transaction.partner_company_id,
        credit_card_transaction.amount,
        credit_card_transaction.foreign_currency,
        credit_card_transaction.foreign_amount,
        array_to_string(credit_card_transaction.reference, private.money_transaction_purpose_delimiter()) as purpose,
        credit_card_transaction.booking_date,
        credit_card_transaction.value_date,
        credit_card_transaction.import_document_id,
        credit_card_transaction.money_category_id,
        credit_card_transaction.note,
        credit_card_transaction.updated_at,
        credit_card_transaction.created_at
$$ language sql immutable;

comment on function public.credit_card_transaction_money_transaction is '@notNull';

----

create function public.cash_transaction_money_transaction(
    cash_transaction public.cash_transaction
) returns public.money_transaction as $$
    select
        cash_transaction.id,
        cash_transaction.account_id,
        cash_transaction."type"::text::public.money_transaction_type,
        cash_transaction.partner_name,
        null::bank_iban as partner_iban,
        cash_transaction.partner_company_id,
        cash_transaction.amount,
        null::currency_code as foreign_currency,
        null::float8 as foreign_amount,
        cash_transaction.purpose,
        cash_transaction.booking_date,
        null::date as value_date,
        cash_transaction.import_document_id,
        cash_transaction.money_category_id,
        cash_transaction.note,
        cash_transaction.updated_at,
        cash_transaction.created_at
$$ language sql immutable;

comment on function public.cash_transaction_money_transaction is '@notNull';

----

create function public.update_money_transaction(
    id                 uuid,
    partner_company_id uuid = null,
    money_category_id  uuid = null
) returns public.money_transaction as $$
declare
    updated_money_transaction public.money_transaction;
begin
    if exists (select from public.bank_transaction where bank_transaction.id = update_money_transaction.id)
    then
        update public.bank_transaction set
            partner_company_id=update_money_transaction.partner_company_id,
            money_category_id=update_money_transaction.money_category_id,
            updated_at=now()
        where bank_transaction.id = update_money_transaction.id
        returning (public.bank_transaction_money_transaction(bank_transaction.*)).*
        into updated_money_transaction;
        delete from public.document_bank_transaction
        where bank_transaction_id = update_money_transaction.id;
        return updated_money_transaction;
    elsif exists (select from public.credit_card_transaction where credit_card_transaction.id = update_money_transaction.id)
    then
        update public.credit_card_transaction set
            partner_company_id=update_money_transaction.partner_company_id,
            money_category_id=update_money_transaction.money_category_id,
            updated_at=now()
        where credit_card_transaction.id = update_money_transaction.id
        returning (public.credit_card_transaction_money_transaction(credit_card_transaction.*)).*
        into updated_money_transaction;
        delete from public.document_credit_card_transaction
        where credit_card_transaction_id = update_money_transaction.id;
        return updated_money_transaction;
    elsif exists (select from public.cash_transaction where cash_transaction.id = update_money_transaction.id)
    then
        update public.cash_transaction set
            partner_company_id=update_money_transaction.partner_company_id,
            money_category_id=update_money_transaction.money_category_id,
            updated_at=now()
        where cash_transaction.id = update_money_transaction.id
        returning (public.cash_transaction_money_transaction(cash_transaction.*)).*
        into updated_money_transaction;
        delete from public.document_cash_transaction
        where cash_transaction_id = update_money_transaction.id;
        return updated_money_transaction;
    end if;
    raise exception 'Money transaction not found';
end
$$ language plpgsql volatile;

----

create function public.update_money_transactions(
    ids                uuid[],
    partner_company_id uuid = null,
    money_category_id  uuid = null
) returns setof public.money_transaction as $$
    select update_money_transaction.*
    from
        unnest(ids) as id,
        public.update_money_transaction(id, partner_company_id, money_category_id)
$$ language sql volatile;

----

create function public.update_money_transaction_note(
    id   uuid,
    note non_empty_text = null
) returns public.money_transaction as $$
declare
    updated_money_transaction public.money_transaction;
begin
    if exists (select from public.bank_transaction where bank_transaction.id = update_money_transaction_note.id)
    then
        update public.bank_transaction set
            note=update_money_transaction_note.note,
            updated_at=now()
        where bank_transaction.id = uupdate_money_transaction_note.id
        returning (public.bank_transaction_money_transaction(bank_transaction.*)).*
        into updated_money_transaction;
        return updated_money_transaction;
    end if;

    if exists (select from public.credit_card_transaction where credit_card_transaction.id = update_money_transaction_note.id)
    then
        update public.credit_card_transaction set
            note=update_money_transaction_note.note,
            updated_at=now()
        where credit_card_transaction.id = uupdate_money_transaction_note.id
        returning (public.credit_card_transaction_money_transaction(credit_card_transaction.*)).*
        into updated_money_transaction;
        return updated_money_transaction;
    end if;

    if exists (select from public.cash_transaction where cash_transaction.id = update_money_transaction_note.id)
    then
        update public.cash_transaction set
            note=update_money_transaction_note.note,
            updated_at=now()
        where cash_transaction.id = uupdate_money_transaction_note.id
        returning (public.cash_transaction_money_transaction(cash_transaction.*)).*
        into updated_money_transaction;
        return updated_money_transaction;
    end if;
end
$$ language plpgsql volatile;
