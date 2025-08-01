CREATE FUNCTION public.filter_accounting_companies(
    search_text text = NULL
) RETURNS SETOF public.accounting_company AS
$$
    SELECT ac.* FROM public.accounting_company AS ac
        INNER JOIN public.company AS c ON (c.id = ac.client_company_id)
    WHERE (
        (COALESCE(TRIM(filter_accounting_companies.search_text), '') = '') OR (
            (
                c.name ILIKE '%' || filter_accounting_companies.search_text || '%'
            ) OR (
                c.brand_name ILIKE '%' || filter_accounting_companies.search_text || '%'    
            ) OR (
                -- TODO-db-201027 check performance of this
                exists (select from public.company_location
                    where company_location.company_id = ac.client_company_id
                    and company_location.vat_id_no ilike '%' || filter_accounting_companies.search_text || '%')
            )
        )
    )
    ORDER BY COALESCE(c.brand_name, c.name)
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION public.filter_accounting_companies IS 'Filter `AccountingCompanies`.';
