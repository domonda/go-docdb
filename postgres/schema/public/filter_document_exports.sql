CREATE FUNCTION public.filter_document_exports(
    client_company_id     uuid,
    export_user_ids       uuid[],
    booking_export        boolean,
    search_text           text,
    from_date             date,
    until_date            date
) RETURNS SETOF public.document_export AS
$$
    SELECT de.* FROM public.document_export AS de
    WHERE (
    	(filter_document_exports.client_company_id IS NULL) OR (
            de.client_company_id = filter_document_exports.client_company_id
        )
    ) AND (
        ((filter_document_exports.export_user_ids IS NULL) OR (array_length(filter_document_exports.export_user_ids, 1) IS NULL)) OR (
            de.user_id = ANY(filter_document_exports.export_user_ids)
        )
    ) AND (
        (filter_document_exports.booking_export IS NULL) OR (
            de.booking_export = filter_document_exports.booking_export
        )
    ) AND (
        (COALESCE(TRIM(filter_document_exports.search_text), '') = '') OR (
            true -- TODO: implement fulltext search
        )
    )
    -- TODO: implement `from_date` and `until_date`
    ORDER BY de.created_at DESC
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION public.filter_document_exports(uuid, uuid[], boolean, text, date, date) IS 'Filter document exports.';
GRANT EXECUTE ON FUNCTION public.filter_document_exports(uuid, uuid[], boolean, text, date, date) TO domonda_user;
