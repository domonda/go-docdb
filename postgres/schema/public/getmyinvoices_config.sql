create table public.getmyinvoices_config (
    id                uuid primary key default uuid_generate_v4(),
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    api_key          text not null check(length(trim(api_key)) > 0),
    from_date        timestamptz,
    import_archived  bool not null default false,
    archive_imported bool not null default true,

    incoming_invoices_document_category_id uuid references public.document_category(id) on delete restrict,
    outgoing_invoices_document_category_id uuid references public.document_category(id) on delete restrict,
    other_documents_document_category_id   uuid references public.document_category(id) on delete restrict,
    constraint any_category check(
        incoming_invoices_document_category_id is not null
        or
        outgoing_invoices_document_category_id is not null
        or
        other_documents_document_category_id is not null
    ),

    created_by  uuid not null references public.user(id) on delete restrict,
	created_at  created_time not null,
    disabled_by uuid references public.user(id) on delete restrict,
    disabled_at timestamptz,
    constraint disabled_by_at check((disabled_by is null) = (disabled_at is null))
);

create index public_getmyinvoices_config_client_company_id_idx on public.getmyinvoices_config(client_company_id);
create index public_getmyinvoices_config_disabled_at_idx       on public.getmyinvoices_config(disabled_at);

grant select, update, insert on table public.getmyinvoices_config to domonda_user;

----

create function public.client_company_current_getmyinvoices_config(
    cc public.client_company
) returns public.getmyinvoices_config as
$$
    select *
    from public.getmyinvoices_config
    where client_company_id = cc.company_id
        and disabled_at is null
        and public.is_client_company_active(cc.company_id)
    order by created_at desc
    limit 1
$$
language sql stable;

comment on function public.client_company_current_getmyinvoices_config is 'Current getmyinvoices config of a client company';

grant execute on function public.client_company_current_getmyinvoices_config to domonda_user;

----

create function public.disable_client_company_getmyinvoices_config(
    client_company_id uuid,
    disabled_by       uuid = private.current_user_id()
) returns uuid as
$$
    update public.getmyinvoices_config as c
       set disabled_by=disable_client_company_getmyinvoices_config.disabled_by,
           disabled_at=now()
     where c.client_company_id = disable_client_company_getmyinvoices_config.client_company_id
       and c.disabled_at is null
 returning c.client_company_id
$$
language sql volatile;

comment on function public.disable_client_company_getmyinvoices_config is 'Disables the current getmyinvoices config of a client company';

grant execute on function public.disable_client_company_getmyinvoices_config to domonda_user;

----

create function public.set_client_company_getmyinvoices_config(
    client_company_id uuid,
    api_key           text,
    from_date         date = null,
    import_archived   bool = false,
    archive_imported  bool = true,
    incoming_invoices_document_category_id uuid = null,
    outgoing_invoices_document_category_id uuid = null,
    other_documents_document_category_id uuid = null,
    created_by uuid = private.current_user_id()
) returns public.getmyinvoices_config as
$$
    with disable_current as (
        select public.disable_client_company_getmyinvoices_config(
            set_client_company_getmyinvoices_config.client_company_id,
            set_client_company_getmyinvoices_config.created_by
        )
    )
    insert into public.getmyinvoices_config (
        client_company_id,
        api_key,
        from_date,
        import_archived,
        archive_imported,
        incoming_invoices_document_category_id,
        outgoing_invoices_document_category_id,
        other_documents_document_category_id,
        created_by
    ) select
        set_client_company_getmyinvoices_config.client_company_id,
        trim(set_client_company_getmyinvoices_config.api_key),
        set_client_company_getmyinvoices_config.from_date,
        set_client_company_getmyinvoices_config.import_archived,
        set_client_company_getmyinvoices_config.archive_imported,
        set_client_company_getmyinvoices_config.incoming_invoices_document_category_id,
        set_client_company_getmyinvoices_config.outgoing_invoices_document_category_id,
        set_client_company_getmyinvoices_config.other_documents_document_category_id,
        set_client_company_getmyinvoices_config.created_by
    from disable_current -- must select from so disable call is not optimized away
    returning *
$$
language sql volatile;

comment on function public.set_client_company_getmyinvoices_config is 'Sets the current getmyinvoices config for a client company';

grant execute on function public.set_client_company_getmyinvoices_config to domonda_user;