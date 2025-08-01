create table public.fastbill_config (
    id                uuid primary key default uuid_generate_v4(),
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    email     email_addr not null,
    api_key   text not null check(length(trim(api_key)) > 0),
    from_date timestamptz, -- TODO-db-201105 use `date` type because it holds just the date

    outgoing_invoices_document_category_id uuid not null references public.document_category(id) on delete restrict,

    created_by  uuid not null references public.user(id) on delete restrict,
	created_at  created_time not null,
    disabled_by uuid references public.user(id) on delete restrict,
    disabled_at timestamptz,
    constraint disabled_by_at check((disabled_by is null) = (disabled_at is null))
);

create index public_fastbill_config_client_company_id_idx on public.fastbill_config(client_company_id);
create index public_fastbill_config_disabled_at_idx       on public.fastbill_config(disabled_at);

grant select, update, insert on table public.fastbill_config to domonda_user;

----

create function public.client_company_current_fastbill_config(
    cc public.client_company
) returns public.fastbill_config as
$$
    select *
    from public.fastbill_config
    where client_company_id = cc.company_id
        and disabled_at is null
        and public.is_client_company_active(cc.company_id)
    order by created_at desc
    limit 1
$$
language sql stable;

comment on function public.client_company_current_fastbill_config is 'Current fastbill config of a client company';

grant execute on function public.client_company_current_fastbill_config to domonda_user;

----

create function public.disable_client_company_fastbill_config(
    client_company_id uuid,
    disabled_by       uuid = private.current_user_id()
) returns uuid as
$$
    update public.fastbill_config as c
       set disabled_by=disable_client_company_fastbill_config.disabled_by,
           disabled_at=now()
     where c.client_company_id = disable_client_company_fastbill_config.client_company_id
       and c.disabled_at is null
 returning c.client_company_id
$$
language sql volatile;

comment on function public.disable_client_company_fastbill_config is 'Disables the current fastbill config of a client company';

grant execute on function public.disable_client_company_fastbill_config to domonda_user;

----

create function public.set_client_company_fastbill_config(
    client_company_id uuid,
    email             text,
    api_key           text,
    outgoing_invoices_document_category_id uuid,
    from_date         date = null,
    created_by uuid = private.current_user_id()
) returns public.fastbill_config as
$$
    with disable_current as (
        select public.disable_client_company_fastbill_config(
            set_client_company_fastbill_config.client_company_id,
            set_client_company_fastbill_config.created_by
        )
    )
    insert into public.fastbill_config (
        client_company_id,
        email,
        api_key,
        from_date,
        outgoing_invoices_document_category_id,
        created_by
    ) select
        set_client_company_fastbill_config.client_company_id,
        set_client_company_fastbill_config.email,
        trim(set_client_company_fastbill_config.api_key),
        set_client_company_fastbill_config.from_date,
        set_client_company_fastbill_config.outgoing_invoices_document_category_id,
        set_client_company_fastbill_config.created_by
    from disable_current -- must select from so disable call is not optimized away
    returning *
$$
language sql volatile;

comment on function public.set_client_company_fastbill_config is 'Sets the current fastbill config for a client company';

grant execute on function public.set_client_company_fastbill_config to domonda_user;