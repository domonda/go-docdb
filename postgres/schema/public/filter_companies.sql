CREATE FUNCTION public.filter_companies(
    not_partners_of_client_company_id uuid = NULL,
    has_client_company                boolean = NULL,
    search_text                       text = NULL
) RETURNS SETOF public.company AS
$$
    SELECT c.* FROM public.company AS c
    WHERE (
        (filter_companies.not_partners_of_client_company_id IS NULL) OR (
            not exists (select from public.partner_company as pc where pc.client_company_id = filter_companies.not_partners_of_client_company_id AND pc.company_id = c.id)
        )
    ) AND (
        (filter_companies.has_client_company IS NULL) OR (
            filter_companies.has_client_company = exists(
                select from public.client_company
                where client_company.company_id = c.id)
        )
    ) AND (
        (COALESCE(TRIM(filter_companies.search_text), '') = '') OR (
            (
                c.name ILIKE '%' || filter_companies.search_text || '%'
            ) OR (
                c.brand_name ILIKE '%' || filter_companies.search_text || '%'
            ) OR (
                c.id::text = filter_companies.search_text
            ) OR (
                -- TODO-db-201027 check performance of this
                exists (select from public.company_location
                    where company_location.company_id = c.id
                    and company_location.vat_id_no ilike '%' || filter_companies.search_text || '%')
            )
        )
    )
    ORDER BY c.name
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION public.filter_companies IS 'Filters `Companies`.';
