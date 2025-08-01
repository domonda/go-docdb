create table private.client_company_abacus_sync_active (
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    active            bool not null,
    created_at        created_time not null
);

create index private_client_company_abacus_sync_active_client_company_id_idx on private.client_company_abacus_sync_active (client_company_id);

grant select, insert on table private.client_company_abacus_sync_active to domonda_user;

----

create function private.is_client_company_abacus_sync_active(
    client_company_id uuid
) returns boolean as
$$
    select coalesce(
        (
            select active from private.client_company_abacus_sync_active
            where client_company_abacus_sync_active.client_company_id = is_client_company_abacus_sync_active.client_company_id
            order by created_at desc
            limit 1
        ),
        false
    )
$$
language sql stable;
