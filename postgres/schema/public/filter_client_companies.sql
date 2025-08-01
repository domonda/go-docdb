create function public.filter_client_companies(
  accounting_company_client_company_id uuid = null,
  search_text                          text = null
) returns setof public.client_company as $$
  select client_company.* from public.client_company
    inner join public.company on company.id = client_company.company_id
  where (filter_client_companies.accounting_company_client_company_id is null
    or client_company.accounting_company_client_company_id = filter_client_companies.accounting_company_client_company_id)
  and (coalesce(trim(filter_client_companies.search_text), '') = ''
    or (
      company.id::text = filter_client_companies.search_text
      or company.name ilike '%' || filter_client_companies.search_text || '%'
      or company.brand_name ilike '%' || filter_client_companies.search_text || '%'
      -- TODO: check performance of this
      or exists (select from public.company_location
          where company_location.company_id = client_company.company_id
          and company_location.vat_id_no ilike '%' || filter_client_companies.search_text || '%')))
  -- the user has to have access to filter for the client
  and (private.current_user_super()
    or exists (
      select from control.client_company_user
      where client_company_user.user_id = private.current_user_id()
      and client_company_user.client_company_id = client_company.company_id))
  order by client_company.email_alias
$$ language sql stable;
