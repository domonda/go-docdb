create table public.export_filename (
    client_company_id uuid not null references public.client_company(company_id) on delete cascade,

    document_pdf text not null check(length(document_pdf) > 0), -- Go template string, see https://pkg.go.dev/text/template

    created_at  created_time not null,
    disabled_at timestamptz
);

create index export_filename_company_id_idx
    on public.export_filename (client_company_id);
create index export_filename_company_id_created_at_idx
    on public.export_filename (client_company_id, created_at)
    where disabled_at is null;

grant select, update, insert on table public.export_filename to domonda_user;


----

create function public.disable_client_company_export_filename(
    client_company_id uuid
) returns uuid as
$$
    update public.export_filename as f
       set disabled_at=now()
     where f.client_company_id = disable_client_company_export_filename.client_company_id
       and f.disabled_at is null
 returning f.client_company_id -- return something
$$
language sql volatile;

comment on function public.disable_client_company_export_filename is 'Disables the current export filename template of a client company';

grant execute on function public.disable_client_company_export_filename to domonda_user;

----

create function public.set_client_company_export_filename(
    client_company_id uuid,
    document_pdf      text
) returns public.export_filename as
$$
    with disable_current as (
        select public.disable_client_company_export_filename(
            set_client_company_export_filename.client_company_id
        )
    )
    insert into public.export_filename (
        client_company_id,
        document_pdf
    ) select
        set_client_company_export_filename.client_company_id,
        set_client_company_export_filename.document_pdf
    from disable_current -- must select from so disable call is not optimized away
    returning *
$$
language sql volatile;

comment on function public.set_client_company_export_filename is 'Sets the current export filename template for a client company';

grant execute on function public.set_client_company_export_filename to domonda_user;