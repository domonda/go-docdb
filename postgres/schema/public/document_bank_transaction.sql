create table public.document_bank_transaction (
    document_id         uuid not null references public.document(id) on delete cascade,
    bank_transaction_id uuid not null references public.bank_transaction(id) on delete cascade,
    primary key(document_id, bank_transaction_id),

    created_by uuid references public.user(id),

    check_id              uuid references matching.check(id),
    check_id_confirmed_by uuid references public.user(id),
    check_id_confirmed_at timestamptz,

    constraint created_by_or_check_id check((created_by is null) <> (check_id is null)),

    -- deprecated
    confidence   float8 not null default 0,
    confirmed_by uuid references public.user(id) on delete set null,
    confirmed_at timestamptz,

    updated_at updated_time not null,
    created_at created_time not null
);

grant select, insert, delete on table public.document_bank_transaction to domonda_user;
grant select on table public.document_bank_transaction to domonda_wg_user;

create index document_bank_transaction_document_id_idx on public.document_bank_transaction (document_id);
create index document_bank_transaction_bank_transaction_id_idx on public.document_bank_transaction (bank_transaction_id);
create index document_bank_transaction_created_at_idx on public.document_bank_transaction (created_at);

----

create function public.add_document_bank_transaction(
    document_id          uuid,
    bank_transaction_id  uuid
) returns public.document_bank_transaction as
$$
    insert into public.document_bank_transaction (
        document_id,
        bank_transaction_id,
        created_by
    ) values (
        add_document_bank_transaction.document_id,
        add_document_bank_transaction.bank_transaction_id,
        (select id from private.current_user())
    )
    returning *
$$
language sql volatile strict;

comment on function public.add_document_bank_transaction is 'Adds a `BankTransaction` match to a `Document`.';

----

create function public.delete_document_bank_transaction(
    document_id          uuid,
    bank_transaction_id  uuid
) returns public.document_bank_transaction as
$$
    delete from public.document_bank_transaction
    where document_id = delete_document_bank_transaction.document_id
        and bank_transaction_id = delete_document_bank_transaction.bank_transaction_id
    returning *
$$
language sql volatile strict;

comment on function public.delete_document_bank_transaction is 'Delete a `BankTransaction` match from a `Document`.';
