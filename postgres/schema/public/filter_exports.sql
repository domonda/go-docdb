create function public.filter_exports(
    client_company_id uuid,
    search_text       text = null,
    booking_export    boolean = null,
    from_date         date = null,
    until_date        date = null
) returns setof public.export as $$
    select export.* from public.export
        inner join public.user on "user".id = export.created_by
    where export.client_company_id = filter_exports.client_company_id
    and (filter_exports.search_text is null
        or (exists (select from public.export_document
            where export_document.export_id = export.id
            and export_document.removed_at is null
           and export_document.document_id::text like '%' || lower(filter_exports.search_text) || '%'))
        or public.user_full_name("user") ilike '%' || lower(filter_exports.search_text) || '%'
        or export.id::text ilike '%' || filter_exports.search_text || '%')
    and (filter_exports.booking_export is null or booking_export = filter_exports.booking_export)
    and (filter_exports.from_date is null or export.created_at >= filter_exports.from_date)
    and (filter_exports.until_date is null or export.created_at <= filter_exports.from_date)
    order by export.created_at desc
$$ language sql stable;
