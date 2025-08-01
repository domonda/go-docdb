create table public.user_default (
    id uuid primary key default uuid_generate_v4(),

    user_id uuid not null unique references public.user(id) on delete cascade,

    client_company_id       uuid references public.client_company(company_id) on delete set null,
    pain001_bank_account_id uuid references public.bank_account(id) on delete set null,

    -- after idle time in minutes
    expire_session int not null default 30 * 1440, -- 1440 minutes in a day

    fintecsystems_bank_connection_init_sync_days int not null default 365,
    constraint fintecsystems_bank_connection_init_sync_days_check check(
        fintecsystems_bank_connection_init_sync_days >= 7
        and fintecsystems_bank_connection_init_sync_days <= 365
    ),

    updated_at updated_time not null,
    created_at created_time not null
);

create index user_default_user_id_idx on public.user_default (user_id);

grant select, update on public.user_default to domonda_user;
grant select, update on public.user_default to domonda_wg_user;

----

create function public.user_default(
    "user" public."user"
) returns public.user_default as $$
    select * from public.user_default where user_id = "user".id
$$ language sql stable strict;

create function public.user_default_expire_session(
    "user" public."user"
) returns int as $$
    select coalesce(
        (public.user_default("user")).expire_session,
        30 * 1440 -- default to 30 days
    )
$$ language sql stable strict;

comment on function public.user_default_expire_session is '@notNull';

----

create function public.upsert_user_default_client_company(
    user_id           uuid,
    client_company_id uuid
) returns public.user_default as $$
declare
    user_default public.user_default;
begin
    if not private.current_user_super()
    and private.current_user_id() <> upsert_user_default_client_company.user_id
    then
        raise exception 'Forbidden';
    end if;

    insert into public.user_default (user_id, client_company_id)
    values (upsert_user_default_client_company.user_id, upsert_user_default_client_company.client_company_id)
    on conflict on constraint user_default_user_id_key do update
        set client_company_id=upsert_user_default_client_company.client_company_id,
            updated_at=now()
    returning * into user_default;

    return user_default;
end;
$$ language plpgsql volatile security definer;

----

create function public.user_default_client_company_id(
    "user" public.user
) returns uuid as $$
    select
        coalesce(
            user_default.client_company_id,
            client_company_user.client_company_id -- first from client company access list
        )
    from public.user
        inner join public.client_company on client_company.company_id = "user".client_company_id
        left join public.user_default on user_default.user_id = "user".id
        left join lateral (
            select *
            from control.client_company_user
            where client_company_user.user_id = "user".id
            limit 1
        ) as client_company_user on true
    where "user".id = user_default_client_company_id."user".id
$$ language sql stable strict;
