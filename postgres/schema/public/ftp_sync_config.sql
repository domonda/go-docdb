create table public.ftp_sync_config (
    id                uuid primary key default uuid_generate_v4(),
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    master_data_url trimmed_text not null,
    -- Append the object numbers to the GL account numbers to make them unique.
	-- NULL is equal to false but also disables any checks for unique GL account texts.
    object_specific_account_nos    boolean,
    accounting_areas_user_accounts boolean not null default false,

    created_by  uuid not null references public.user(id) on delete restrict,
	created_at  created_time not null,
    disabled_by uuid references public.user(id) on delete restrict,
    disabled_at timestamptz,
    constraint disabled_by_at check((disabled_by is null) = (disabled_at is null))
);

create index ftp_sync_config_client_company_id_idx on public.ftp_sync_config(client_company_id);
create index ftp_sync_config_disabled_at_idx       on public.ftp_sync_config(disabled_at);

grant select, update, insert on table public.ftp_sync_config to domonda_user;

----

create function public.client_company_current_ftp_sync_config(
    cc public.client_company
) returns public.ftp_sync_config as
$$
    select *
    from public.ftp_sync_config
    where client_company_id = cc.company_id
        and disabled_at is null
        and public.is_client_company_active(cc.company_id)
    order by created_at desc
    limit 1
$$
language sql stable;

comment on function public.client_company_current_ftp_sync_config is 'Current FTP sync config of a client company';

grant execute on function public.client_company_current_ftp_sync_config to domonda_user;

----

create function public.disable_client_company_ftp_sync_config(
    client_company_id uuid,
    disabled_by       uuid = private.current_user_id()
) returns uuid as
$$
    update public.ftp_sync_config as c
       set disabled_by=disable_client_company_ftp_sync_config.disabled_by,
           disabled_at=now()
     where c.client_company_id = disable_client_company_ftp_sync_config.client_company_id
       and c.disabled_at is null
 returning c.id
$$
language sql volatile;

comment on function public.disable_client_company_ftp_sync_config is 'Disables the current FTP sync config of a client company';

grant execute on function public.disable_client_company_ftp_sync_config to domonda_user;

----

create function public.set_client_company_ftp_sync_config(
    client_company_id              uuid,
    master_data_url                trimmed_text,
    object_specific_account_nos    boolean = null,
    accounting_areas_user_accounts boolean = false,
    created_by                     uuid = private.current_user_id()
) returns public.ftp_sync_config as
$$
    with disable_current as (
        select public.disable_client_company_ftp_sync_config(
            set_client_company_ftp_sync_config.client_company_id,
            set_client_company_ftp_sync_config.created_by
        )
    )
    insert into public.ftp_sync_config (
        client_company_id,
        master_data_url,
        object_specific_account_nos,
        accounting_areas_user_accounts,
        created_by
    ) select
        set_client_company_ftp_sync_config.client_company_id,
        set_client_company_ftp_sync_config.master_data_url,
        set_client_company_ftp_sync_config.object_specific_account_nos,
        set_client_company_ftp_sync_config.accounting_areas_user_accounts,
        set_client_company_ftp_sync_config.created_by
    from disable_current -- must select from so disable call is not optimized away
    returning *
$$
language sql volatile;

comment on function public.set_client_company_ftp_sync_config is 'Sets the current FTP sync config for a client company';

grant execute on function public.set_client_company_ftp_sync_config to domonda_user;