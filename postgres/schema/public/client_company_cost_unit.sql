create table public.client_company_cost_unit (
    id                uuid primary key default uuid_generate_v4(),
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    "number" text not null,
    constraint number_check check((length(trim("number")) > 0) and (length(trim("number")) <= 20)), -- 20 is the max for BMD

    description text not null check(length(trim(description)) > 0),

    -- If historic IS NOT NULL then the cost center is treated as historic,
    -- independent of value of the timestamp.
    -- historic is included in the unique check, so historic cost centers
    -- can share the same "number", description, while non historic can not
    historic timestamptz,

    currency currency_code not null default 'EUR',
    budget   float8        check(budget > 0),

    updated_at updated_time not null,
    created_at created_time not null
);

grant select, insert, update, delete on table public.client_company_cost_unit TO domonda_user;
grant select on table public.client_company_cost_unit to domonda_wg_user; -- TODO: other grants

create unique index client_company_cost_unit_number
    on public.client_company_cost_unit (client_company_id, "number")
    where historic is null;

create index client_company_cost_unit_description
    on public.client_company_cost_unit (client_company_id, description);

----

create function public.create_client_company_cost_unit(
    client_company_id uuid,
    "number"          text,
    description       text,
    currency          currency_code = 'EUR',
    budget            float8 = null
) returns public.client_company_cost_unit as
$$
    insert into public.client_company_cost_unit (
        id,
        client_company_id,
        "number",
        description,
        currency,
        budget
    ) values (
        uuid_generate_v4(),
        create_client_company_cost_unit.client_company_id,
        create_client_company_cost_unit.number,
        create_client_company_cost_unit.description,
        create_client_company_cost_unit.currency,
        create_client_company_cost_unit.budget
    ) returning *
$$
language sql volatile;
comment on function public.create_client_company_cost_unit is
'Creates a new `ClientCompanyCostUnit`.';

create function public.update_client_company_cost_unit(
    id          uuid,
    "number"    text,
    description text,
    currency currency_code = null,
    budget   float8 = null
) returns public.client_company_cost_unit as
$$
    update public.client_company_cost_unit
        set
            "number"=update_client_company_cost_unit.number,
            description=update_client_company_cost_unit.description,
            currency=coalesce(
                update_client_company_cost_unit.currency,
                (select currency from public.client_company_cost_unit where id = update_client_company_cost_unit.id for update)
            ),
            budget=update_client_company_cost_unit.budget,
            updated_at=now()
        where id = update_client_company_cost_unit.id
    returning *
$$
language sql volatile;
comment on function public.update_client_company_cost_unit is
'Updates an existing `ClientCompanyCostUnit`.';

create function public.delete_client_company_cost_unit(
    id uuid
) returns public.client_company_cost_unit as
$$
    delete from public.client_company_cost_unit
    where id = delete_client_company_cost_unit.id
    returning *
$$
language sql volatile;

----

create function public.filter_client_company_cost_units(
    client_company_id uuid,
    search_text       text = null
) returns setof public.client_company_cost_unit as $$
    select * from public.client_company_cost_unit
    where (
        client_company_id = filter_client_company_cost_units.client_company_id
    ) and (
        historic is null
    ) and (
        (coalesce(trim(filter_client_company_cost_units.search_text), '') = '') or (
            (
                "number" ilike '%' || filter_client_company_cost_units.search_text || '%'
            ) or (
                description ilike '%' || filter_client_company_cost_units.search_text || '%'
            )
        )
    )
    order by "number"
$$ language sql stable;
comment on function public.filter_client_company_cost_units is
'Filters `ClientCompanyCostUnits`.';

create function public.client_company_cost_unit_full_name(
    client_company_cost_unit public.client_company_cost_unit
) returns text as $$
    select client_company_cost_unit.number || ' / ' || client_company_cost_unit.description
$$ language sql immutable;
comment on function public.client_company_cost_unit_full_name is '@notNull';

create function public.client_company_cost_units_by_ids(
    ids uuid[]
) returns setof public.client_company_cost_unit as $$
    select * from public.client_company_cost_unit where id = any(ids)
$$ language sql stable strict;
