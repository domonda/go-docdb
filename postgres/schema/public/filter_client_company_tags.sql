CREATE FUNCTION public.filter_client_company_tags(
    client_company_id uuid,
    search_text       text = NULL
) RETURNS SETOF public.client_company_tag AS
$$
    SELECT * FROM public.client_company_tag WHERE (
        client_company_id = filter_client_company_tags.client_company_id
    ) AND (
        (COALESCE(TRIM(filter_client_company_tags.search_text), '') = '') OR (
            tag ILIKE '%' || filter_client_company_tags.search_text || '%'
        )
    )
    ORDER BY tag DESC
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION public.filter_client_company_tags IS 'Filters `CompanyTags`.';
