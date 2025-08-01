create type public.partner_account_type as enum (
    'VENDOR', -- purchase from
    'CLIENT'  -- sell to
);

-- NOTE: if there are multiple account numbers for a single partner, sort by account number in asc order and take the first one
create table public.partner_account (
    id uuid primary key default uuid_generate_v4(),

    client_company_id  uuid not null references public.client_company(company_id) on delete cascade,
    partner_company_id uuid not null references public.partner_company(id) on delete cascade,
    "type"             public.partner_account_type not null,
    "number"           account_no not null,

    -- number is unique across client company
    constraint partner_account_number_uniqueness
        unique(client_company_id, "number")
        deferrable initially deferred, -- Needed to change multiple colliding numbers within one transaction. See https://emmer.dev/blog/deferrable-constraints-in-postgresql/

    description trimmed_text,
    source      text not null default 'UNKNOWN',
    currency    currency_code,

    disabled_at timestamptz,
    updated_at  updated_time not null,
    created_at  created_time not null
);

grant all on public.partner_account to domonda_user;
grant select on public.partner_account to domonda_wg_user;

-- NOTE: have to create the unique index this way, because postgres < 15 handles null values as distinct
create unique index partner_account_type_currency_uniqueness on public.partner_account (partner_company_id, "type", currency) where currency is not null;
create unique index partner_account_type_uniqueness          on public.partner_account (partner_company_id, "type")           where currency is null;

create index partner_account_client_company_id_idx  on public.partner_account (client_company_id);
create index partner_account_partner_company_id_idx on public.partner_account (partner_company_id);
create index partner_account_number_idx             on public.partner_account ("number");
create index partner_account_number_bigint_idx      on public.partner_account (private.text_to_bigint("number"));
create index partner_account_disabled_at_idx        on public.partner_account (disabled_at);

comment on table public.partner_account is 'Accounting relevant sub-ledger (Personenkonten) data of a business partner.';

----

create function public.partner_account_active(
    partner_account public.partner_account
) returns boolean as $$
    select partner_account.disabled_at is null
$$ language sql immutable strict;
comment on function public.partner_account_active is '@notNull';

----

create function public.create_partner_account(
    partner_company_id uuid,
    "type"             public.partner_account_type,
    "number"           account_no,
    description        text = null,
    currency           currency_code = null
) returns public.partner_account as
$$
    insert into public.partner_account (
        "client_company_id",
        "partner_company_id",
        "type",
        "number",
        "description",
        "source",
        "currency"
    ) values (
        (select client_company_id from public.partner_company where partner_company.id = create_partner_account.partner_company_id),
        create_partner_account.partner_company_id,
        create_partner_account.type,
        create_partner_account.number,
        create_partner_account.description,
        'USER',
        create_partner_account.currency
    )
    returning *
$$
language sql volatile;

comment on function public.create_partner_account is '@notNull';


----

create function public.update_partner_account(
    id                 uuid,
    partner_company_id uuid,
    "type"             public.partner_account_type,
    "number"           account_no,
    description        text = null,
    currency           currency_code = null,
    active             boolean = true
) returns public.partner_account as
$$
    update public.partner_account
    set
        partner_company_id=update_partner_account.partner_company_id,
        "type"=update_partner_account.type,
        "number"=update_partner_account.number,
        description=update_partner_account.description,
        currency=update_partner_account.currency,
        disabled_at=(
            case when active then null
            else (
                select coalesce(a.disabled_at, now())
                from public.partner_account as a
                where a.id = update_partner_account.id
            ) end
        ),
        updated_at=now()
    where id = update_partner_account.id
    returning *
$$
language sql volatile;

comment on function public.update_partner_account is 'Update an existing `PartnerAccount`.';

----

create function public.delete_partner_account(
    id uuid
) returns public.partner_account as
$$
    delete from public.partner_account
    where id = delete_partner_account.id
    returning *
$$
language sql volatile strict;

----

create function public.clone_partner_accounts(src_client_company_id uuid, dst_client_company_id uuid)
returns setof public.partner_account
language plpgsql volatile as
$$
begin
    insert into public.partner_company (
        client_company_id,
        company_id,
        name,
        user_id,
        alternative_names,
        source,
        paid_with_direct_debit
    )
    select
        dst_client_company_id,
        src_pc.company_id,
        src_pc.name,
        src_pc.user_id,
        src_pc.alternative_names,
        'cloned from '||src_pc.id::text, -- source
        src_pc.paid_with_direct_debit
    from public.partner_company as src_pc
    where src_pc.client_company_id = src_client_company_id
    and (src_pc.company_id is null or src_pc.company_id <> dst_client_company_id)
    on conflict do nothing;

    return query
    insert into public.partner_account (
        client_company_id,
        partner_company_id,
        "type",
        "number",
        description,
        source,
        currency
    )
    select
        dst_client_company_id,
        (    -- partner_company_id
            select dst_pc.id
            from public.partner_company as dst_pc
            where dst_pc.client_company_id = dst_client_company_id
            and exists (
                select from public.partner_company as src_pc
                where src_pc.client_company_id = src_client_company_id
                and src_pc.id = src_pa.partner_company_id
                and ((
                    src_pc.company_id is not null
                    and dst_pc.company_id is not null
                    and src_pc.company_id = dst_pc.company_id
                ) or (
                    src_pc.name is not null
                    and dst_pc.name is not null
                    and src_pc.name = dst_pc.name
                ))
            )
        ),
        src_pa.type,
        src_pa.number,
        src_pa.description,
        'cloned from '||src_pa.id::text, -- source
        src_pa.currency
    from public.partner_account as src_pa
    where src_pa.client_company_id = src_client_company_id
    returning *;
end
$$;

----

-- create function public.client_company_max_partner_account_length(
--     client public.client_company
-- ) returns int as
-- $$
--     select length("number")
--         from public.partner_account
--         where client_company_id = client.company_id
-- $$
-- language sql stable;

-- comment on function public.client_company_max_partner_account_length is 'Maximum partner accont number length of the client company.';