create view api.export with (security_barrier) as
select
    id,
    client_company_id,
    spreadsheets    as has_spreadsheets,
    pdfs            as has_pdfs,
    audit_trail_pos as audit_trail,
    accounting_export,
    accounting_period,
    booking_export,
    allow_incomplete,
    created_by,
    created_at
from public.export
where client_company_id = api.current_client_company_id();

grant select on table api.export to domonda_api;

comment on column api.export.client_company_id is '@notNull';
comment on column api.export.has_spreadsheets is '@notNull';
comment on column api.export.has_pdfs is '@notNull';
comment on column api.export.audit_trail is '@notNull';
comment on column api.export.booking_export is '@notNull';
comment on column api.export.allow_incomplete is '@notNull';
comment on column api.export.created_by is '@notNull';
comment on column api.export.created_at is '@notNull';
comment on view api.export is $$
@primaryKey id
@foreignKey (client_company_id) references api.client_company (company_id)
@foreignKey (created_by) references api.user (id)
$$;

----

create view api.export_document with (security_barrier) as
select
    ed.export_id,
    ed.document_id,
    ed.removed_at,
    ed.removed_by
from public.export_document as ed
    join public.export on ed.export_id = export.id
where export.client_company_id = api.current_client_company_id();

grant select on table api.export_document to domonda_api;

comment on column api.export_document.export_id is '@notNull';
comment on column api.export_document.document_id is '@notNull';
comment on view api.export_document is $$
@primaryKey export_id, document_id
@foreignKey (export_id) references api.export (id)
@foreignKey (document_id) references public.document (id)
@foreignKey (removed_by) references api.user (id)
$$;


create function api.export_documents(e api.export) returns setof api.document
language sql stable strict as
$$
    select d.*
    from api.document as d
        join api.export_document as ed on ed.document_id = d.id
    where ed.export_id = e.id
$$;

----

create function api.mark_documents_as_booked(
    document_ids      uuid[],
    accounting_period date = CURRENT_DATE,
    booked_by_user_id uuid = 'b2e0ed5c-b25a-4fee-854f-a33a4bc682f6', -- API system user
    archive           boolean = false
) returns api.export
language plpgsql security definer as
$$
declare
    client_company_ids uuid[];
    export_id uuid;
    doc_id uuid;
    result api.export;
begin
    if (select count(*) from public.document where id = any(document_ids)) != cardinality(document_ids) then
        raise exception 'Not all documents exist';
    end if;

    if (select count(distinct id) from public.document where id = any(document_ids)) != cardinality(document_ids) then
        raise exception 'Documents must be unique';
    end if;

    select array_agg(distinct client_company_id) into client_company_ids
    from public.document
    where id = any(document_ids);

    if cardinality(client_company_ids) > 1 then
        raise exception 'Documents must be from the same client company';
    end if;

    insert into public.export (
        client_company_id,
        created_by,
        created_at,
        accounting_export,
        accounting_period,
        booking_export,
        allow_incomplete
    ) values (
        client_company_ids[1],
        booked_by_user_id, -- created_by
        now(),             -- created_at
        'CUSTOM_BOOKED',   -- accounting_export
        accounting_period, -- accounting_period
        true,              -- booking_export
        true               -- allow_incomplete
    )
    returning id into export_id;

    foreach doc_id in array document_ids loop
        insert into public.export_document (
            export_id,
            document_id,
            document_version_id,
            removed_at,
            removed_by
        )
        select
            export_id,
            doc_id,
            ver.id,
            null,
            null
        from docdb.document_version as ver
        where exists (
            select from public.document as doc
            where doc.id = doc_id
                and doc.id = ver.document_id
                and date_trunc('milliseconds', doc.version) = date_trunc('milliseconds', ver.version)
        );

        if mark_documents_as_booked.archive then
            update public.document
            set archived=true, updated_at=now()
            where id = doc_id;

            -- private.current_user_id() is null so private.document_log_archived_or_unarchived()
            -- wont create a document_log create a log entry manually
            insert into public.document_log ("type", document_id, user_id)
            values ('ARCHIVED'::public.document_log_type, doc_id, booked_by_user_id);
        end if;
    end loop;

    select * from api.export where id = export_id
        into result;
    return result;
end
$$;
comment on function api.mark_documents_as_booked is 'Marks all documents in `documentRowIds` for the `accountingPeriod` as booked. You can change the user who booked the documents by providing a `bookedByUserId`. If `archive` is true, the documents will be archived as well.';
