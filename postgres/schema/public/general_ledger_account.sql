create table public.general_ledger_account (
    id uuid primary key default uuid_generate_v4(),

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    "number"          account_no not null,

    -- number is unique across client company
    constraint gl_account_number_uniqueness
        unique(client_company_id, "number")
        deferrable initially deferred, -- Needed to change multiple colliding numbers within one transaction. See https://emmer.dev/blog/deferrable-constraints-in-postgresql/

    currency currency_code, -- not used for now

    name     trimmed_text,
    category trimmed_text,

    disabled_at timestamptz,
    updated_at  updated_time not null,
    created_at  created_time not null
);

create index general_ledger_account_client_company_id_idx
    on public.general_ledger_account (client_company_id);
create index general_ledger_account_number_idx
    on public.general_ledger_account ("number");
create index general_ledger_account_client_company_id_number_idx
    on public.general_ledger_account (client_company_id, "number");
create index general_ledger_account_trgm_idx
    on public.general_ledger_account using gin (("number"::text) gin_trgm_ops, name gin_trgm_ops, category gin_trgm_ops);
create index general_ledger_account_numeric_number_idx
    on public.general_ledger_account ((substring("number" from '(\d+)')::numeric));
create index general_ledger_account_disabled_at_idx
    on public.general_ledger_account (disabled_at);


grant select, insert, update, delete on table public.general_ledger_account to domonda_user;
grant select on public.general_ledger_account to domonda_wg_user;

----

create function public.general_ledger_account_full_name(
    general_ledger_account public.general_ledger_account
) returns text as $$
    select case
        when coalesce(general_ledger_account.name, general_ledger_account.category) is not null
        then general_ledger_account.number || ' / ' || coalesce(general_ledger_account.name, general_ledger_account.category)
        else general_ledger_account.number
    end
$$ language sql stable strict;
comment on function public.general_ledger_account_full_name is '@notNull';


create function public.general_ledger_account_number_as_number(
    general_ledger_account public.general_ledger_account
) returns numeric as $$
    select substring(general_ledger_account."number" from '(\d+)')::numeric
$$ language sql immutable strict;

create index general_ledger_account_number_as_number_idx
    on public.general_ledger_account (public.general_ledger_account_number_as_number(general_ledger_account));


create function public.general_ledger_account_active(
    general_ledger_account public.general_ledger_account
) returns boolean as $$
    select general_ledger_account.disabled_at is null
$$ language sql immutable strict;
comment on function public.general_ledger_account_active is '@notNull';

----

create function public.create_general_ledger_account(
    client_company_id uuid,
    "number"          account_no,
    "name"            text = null,
    category          text = null
) returns public.general_ledger_account as
$$
    insert into public.general_ledger_account (id, client_company_id, "number", "name", category)
    values (uuid_generate_v4(), create_general_ledger_account.client_company_id, create_general_ledger_account.number, create_general_ledger_account.name, create_general_ledger_account.category)
    returning *
$$
language sql volatile;

comment on function public.create_general_ledger_account is 'Create a `GeneralLedgerAccount` for the `ClientCompany`.';

----

create function public.update_general_ledger_account(
    id       uuid,
    "number" account_no,
    "name"   text = null,
    category text = null,
    active   boolean = true
) returns public.general_ledger_account as
$$
    update public.general_ledger_account
    set
        "number"=update_general_ledger_account.number,
        "name"=update_general_ledger_account.name,
        category=update_general_ledger_account.category,
        disabled_at=(
            case when active then null
            else (
                select coalesce(a.disabled_at, now())
                from public.general_ledger_account as a
                where a.id = update_general_ledger_account.id
            ) end
        ),
        updated_at=now()
    where id = update_general_ledger_account.id
    returning *
$$
language sql volatile;

comment on function public.update_general_ledger_account is 'Update an existing `GeneralLedgerAccount`.';

----

create function public.delete_general_ledger_account(
    id uuid
) returns public.general_ledger_account as
$$
    delete from public.general_ledger_account
    where id = delete_general_ledger_account.id
    returning *
$$
language sql volatile;

comment on function public.delete_general_ledger_account is 'Delete a `GeneralLedgerAccount`.';

----

-- create function public.client_company_max_gl_account_number_length(
--     client public.client_company
-- ) returns int as
-- $$
--     select length("number")
--         from public.general_ledger_account
--         where client_company_id = client.company_id
-- $$
-- language sql stable;

-- comment on function public.client_company_max_gl_account_number_length is 'Maximum general ledger accont number length of the client company.';

----

create function public.compatible_general_ledger_accounts(
    check_client_company_id uuid,
    ref_client_company_id   uuid
) returns boolean
language sql stable as $$
    with ref as (
        select "number"
        from public.general_ledger_account
        where client_company_id = ref_client_company_id
    )
    select count(*) > 0 and count(*) = (select count(*) from ref)
    from public.general_ledger_account
    where client_company_id = check_client_company_id
        and exists (
            select from ref where "number" = general_ledger_account.number
        )
$$;

comment on function public.compatible_general_ledger_accounts is 'Returns true if all general ledger account numbers of a reference client company also exist in the check client company';

----

create type public.chart_of_accounts_with_number_length as (
    chart_of_accounts public.chart_of_accounts,
    gl_number_length  int
);

create function public.detect_chart_of_accounts(
    client_company_id uuid
) returns public.chart_of_accounts_with_number_length
language sql as $$
    select
        (
            ref.chart_of_accounts, ref.gl_number_length
        )::public.chart_of_accounts_with_number_length
    from
        (values
            ('SKR03'::public.chart_of_accounts, 4, '48991b55-2355-4344-8fa1-70d01a977333'::uuid),
            ('SKR03'::public.chart_of_accounts, 5, '9be5ff04-df6c-485a-8848-8e5e426737c6'::uuid),
            ('SKR03'::public.chart_of_accounts, 6, 'ef437b87-bcb5-44b3-98ec-611867ddda05'::uuid),
            ('SKR03'::public.chart_of_accounts, 7, 'd24a80bd-5b73-401f-aa1e-4fbcdb61aa80'::uuid),
            -- ('SKR04'::public.chart_of_accounts, 4, 'd6c816ef-3f43-427c-a40a-ba85acf59364'::uuid), -- gl accounts missing
            ('SKR04'::public.chart_of_accounts, 5, '1f521e1d-7565-4bb9-ad44-4cef2f98622a'::uuid),
            -- ('SKR04'::public.chart_of_accounts, 6, '78ed288f-f4e6-4521-9659-e1d1ea84cc60'::uuid), -- gl accounts missing
            ('SKR04'::public.chart_of_accounts, 7, '148100ef-dbc7-4919-a58f-738857b0727e'::uuid)
        ) as ref (chart_of_accounts, gl_number_length, client_company_id)
    where
        public.compatible_general_ledger_accounts(
            detect_chart_of_accounts.client_company_id,
            ref.client_company_id
        )
$$;

comment on function public.detect_chart_of_accounts is 'Detects the chart of accounts and general ledger number length of a client company by comparing with a list of reference companies';

----

create function public.general_ledger_accounts_by_ids(
    ids uuid[]
) returns setof public.general_ledger_account as $$
    select * from public.general_ledger_account where id = any(ids)
$$ language sql stable strict;
