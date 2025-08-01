CREATE TYPE public.cash_transaction_type AS ENUM (
    'INCOMING',
    'OUTGOING'
);

COMMENT ON TYPE public.cash_transaction_type IS 'Type of the `CashTransaction`.';

----

-- uniqueness: (account_id, "type", amount, purpose, booking_date)

CREATE TABLE public.cash_transaction (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    account_id uuid NOT NULL REFERENCES public.cash_account(id) ON DELETE CASCADE,

    partner_name       text,
    partner_company_id uuid REFERENCES public.partner_company(id) ON DELETE SET NULL,

    "type" public.cash_transaction_type NOT NULL,
    amount float8 NOT NULL,

    purpose text NOT NULL CHECK(length(purpose) > 0),

    booking_date date NOT NULL,

    -- NOTE: import document represents the document from which this transaction originates
    import_document_id uuid REFERENCES public.document(id) ON DELETE CASCADE,

    -- when in category, a transaction is considered matched (no belonging document)
    money_category_id uuid references public.money_category(id) on delete restrict,

    note text,
    constraint note_non_empty_check check(length(trim(note)) > 0),

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL,

    CONSTRAINT cash_transaction_uniqueness UNIQUE (account_id, "type", partner_name, amount, purpose, booking_date)
);

grant all on public.cash_transaction to domonda_user;
grant select on table public.cash_transaction to domonda_wg_user;

CREATE INDEX cash_transaction_account_id_idx ON public.cash_transaction (account_id);
CREATE INDEX cash_transaction_partner_name_idx ON public.cash_transaction using gin (partner_name gin_trgm_ops);
CREATE INDEX cash_transaction_partner_company_id_idx ON public.cash_transaction (partner_company_id);
CREATE INDEX cash_transaction_import_document_id_idx ON public.cash_transaction (import_document_id);
CREATE INDEX cash_transaction_purpose_idx ON public.cash_transaction using gin (purpose gin_trgm_ops);
CREATE INDEX cash_transaction_booking_date_idx ON public.cash_transaction (booking_date);
CREATE INDEX cash_transaction_money_category_id_idx ON public.cash_transaction (money_category_id);

----

create function public.cash_account_balance_today(
    cash_account public.cash_account
) returns float8 as $$
declare
    balance_today float8;
begin
    if cash_account.balance_at_date is null
    then
        return cash_account.balance;
    end if;

    select sum(case "type" when 'OUTGOING' then amount * -1 else amount end)
    into balance_today
    from public.cash_transaction
    where cash_transaction.booking_date > cash_account.balance_at_date
    and cash_transaction.account_id = cash_account.id;

    return balance_today + cash_account.balance;
end
$$ language plpgsql stable strict;

----

create function public.cash_account_balance_until(
    cash_account public.cash_account,
    until_date   date = null
) returns float8 as $$
declare
    balance_until float8;
begin
    if cash_account.balance_at_date is null
    then
        return cash_account.balance;
    end if;

    select sum(case "type" when 'OUTGOING' then amount * -1 else amount end)
    into balance_until
    from public.cash_transaction
    where cash_transaction.account_id = cash_account.id
    and cash_transaction.booking_date >= cash_account.balance_at_date
    and (
        until_date is null
        or cash_transaction.booking_date <= until_date
    );

    return balance_until + cash_account.balance;
end
$$ language plpgsql stable;

----

create function public.create_cash_transaction(
    account_id uuid,
    "type" public.cash_transaction_type,
    amount float8,
    purpose text,
    booking_date date,
    partner_company_id uuid = null,
    money_category_id uuid = null
) returns public.cash_transaction as $$
    insert into public.cash_transaction (account_id, partner_company_id, "type", amount, purpose, booking_date, money_category_id)
    values (
        create_cash_transaction.account_id,
        create_cash_transaction.partner_company_id,
        create_cash_transaction."type",
        create_cash_transaction.amount,
        create_cash_transaction.purpose,
        create_cash_transaction.booking_date,
        create_cash_transaction.money_category_id
    )
    returning *
$$ language sql volatile;

create function public.create_cash_transaction_and_document_cash_transaction(
    document_id uuid,
    account_id uuid,
    "type" public.cash_transaction_type,
    amount float8,
    purpose text,
    booking_date date,
    partner_company_id uuid = null,
    money_category_id uuid = null
) returns public.cash_transaction as $$
declare
    created_cash_transaction public.cash_transaction;
begin
    created_cash_transaction := public.create_cash_transaction(
        create_cash_transaction_and_document_cash_transaction.account_id,
        create_cash_transaction_and_document_cash_transaction."type",
        create_cash_transaction_and_document_cash_transaction.amount,
        create_cash_transaction_and_document_cash_transaction.purpose,
        create_cash_transaction_and_document_cash_transaction.booking_date,
        create_cash_transaction_and_document_cash_transaction.partner_company_id,
        create_cash_transaction_and_document_cash_transaction.money_category_id
    );

    insert into public.document_cash_transaction (document_id, cash_transaction_id, created_by)
    values (create_cash_transaction_and_document_cash_transaction.document_id, created_cash_transaction.id, private.current_user_id());

    return created_cash_transaction;
end
$$ language plpgsql volatile;

create function public.update_cash_transaction(
    id uuid,
    account_id uuid,
    "type" public.cash_transaction_type,
    amount float8,
    purpose text,
    booking_date date,
    partner_company_id uuid = null,
    money_category_id uuid = null
) returns public.cash_transaction as $$
    update public.cash_transaction
    set
        partner_company_id=update_cash_transaction.partner_company_id,
        account_id=update_cash_transaction.account_id,
        "type"=update_cash_transaction."type",
        amount=update_cash_transaction.amount,
        purpose=update_cash_transaction.purpose,
        booking_date=update_cash_transaction.booking_date,
        money_category_id=update_cash_transaction.money_category_id,
        updated_at=now()
    where cash_transaction.id = update_cash_transaction.id
    returning *
$$ language sql volatile;

create function public.delete_cash_transaction(
    id uuid
) returns public.cash_transaction as $$
    delete from public.cash_transaction
    where cash_transaction.id = delete_cash_transaction.id
    returning *
$$ language sql volatile;
