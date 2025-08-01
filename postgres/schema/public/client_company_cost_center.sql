create table public.client_company_cost_center (
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

    updated_at updated_time not null,
    created_at created_time not null
);

grant select, insert, update, delete on table public.client_company_cost_center TO domonda_user;
grant select on table public.client_company_cost_center to domonda_wg_user; -- TODO: other grants

create unique index client_company_cost_center_number
    on public.client_company_cost_center (client_company_id, "number")
    where historic is null;

create index client_company_cost_center_description
    on public.client_company_cost_center (client_company_id, description);

----

create function public.create_client_company_cost_center(
    client_company_id uuid,
    "number"          text,
    description       text,
    currency          currency_code = 'EUR'
) returns public.client_company_cost_center as
$$
    insert into public.client_company_cost_center (
        id,
        client_company_id,
        "number",
        description,
        currency
    ) values (
        uuid_generate_v4(),
        create_client_company_cost_center.client_company_id,
        create_client_company_cost_center.number,
        create_client_company_cost_center.description,
        create_client_company_cost_center.currency
    ) returning *
$$
language sql volatile;

grant execute on function public.create_client_company_cost_center to domonda_user;

comment on function public.create_client_company_cost_center is 'Creates a new `ClientCompanyCostCenter`.';

----

create function public.update_client_company_cost_center(
    id          uuid,
    "number"    text,
    description text,
    currency currency_code = null
) returns public.client_company_cost_center as
$$
    update public.client_company_cost_center
        set
            "number"=update_client_company_cost_center.number,
            description=update_client_company_cost_center.description,
            currency=coalesce(
                update_client_company_cost_center.currency,
                (select currency from public.client_company_cost_center where id = update_client_company_cost_center.id for update)
            ),
            updated_at=now()
        where id = update_client_company_cost_center.id
    returning *
$$
language sql volatile;

grant execute on function public.update_client_company_cost_center to domonda_user;


----

create function public.delete_client_company_cost_center(
    id uuid
) returns public.client_company_cost_center as
$$
    delete from public.client_company_cost_center
    where id = delete_client_company_cost_center.id
    returning *
$$
language sql volatile;

grant execute on function public.delete_client_company_cost_center(uuid) to domonda_user;

----

create function public.filter_client_company_cost_centers(
    client_company_id uuid,
    search_text       text = null
) returns setof public.client_company_cost_center as
$$
    select * from public.client_company_cost_center
    where (
        client_company_id = filter_client_company_cost_centers.client_company_id
    ) and (
        historic is null
    ) and (
        (coalesce(trim(filter_client_company_cost_centers.search_text), '') = '') or (
            (
                "number" ilike '%' || filter_client_company_cost_centers.search_text || '%'
            ) or (
                description ilike '%' || filter_client_company_cost_centers.search_text || '%'
            )
        )
    )
    order by "number"
$$
language sql stable;

comment on function public.filter_client_company_cost_centers is 'Filters `ClientCompanyCostCenters`.';

----

create function public.client_company_cost_center_full_name(
    client_company_cost_center public.client_company_cost_center
) returns text as
$$
    select client_company_cost_center.number || ' / ' || client_company_cost_center.description
$$
language sql immutable;

comment on function public.client_company_cost_center_full_name is '@notNull';


----

create function public.client_company_cost_centers_by_ids(
    ids uuid[]
) returns setof public.client_company_cost_center as $$
    select * from public.client_company_cost_center where id = any(ids)
$$ language sql stable strict;
