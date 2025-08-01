create function public.filter_partner_accounts(
  client_company_id uuid,
  search_text       text = null,
  active            boolean = null,
  "type"            public.partner_account_type = null,
  -- partner_company
  exclude_partner_company_ids boolean = false,
  partner_company_ids         uuid[] = null
) returns setof public.partner_account as $$
  select pa.* from public.partner_account as pa
    inner join public.partner_company as pc on pc.id = pa.partner_company_id
  where pc.client_company_id = filter_partner_accounts.client_company_id
  and (
    coalesce(trim(search_text), '') = ''
    or (
      pa.number ilike '%' || search_text || '%'
      or pa.description ilike '%' || search_text || '%'
      or pa.source ilike '%' || search_text || '%'
      -- TODO-db-201027 check performance of this
      or pc.derived_name ilike '%' || search_text || '%'
      -- TODO-db-201027 check performance of this
      or exists (
        select from public.partner_company_locations(pc) as company_location
        where company_location.vat_id_no ilike '%' || search_text || '%'
      )
    )
  ) and (
    filter_partner_accounts.active is null
    or (pa.disabled_at is null) = filter_partner_accounts.active
  ) and (
    filter_partner_accounts.type is null
    or pa.type = filter_partner_accounts.type
  ) and (
    partner_company_ids is null
    or (
      case when array_length(partner_company_ids, 1) is null
        -- empty slice
        then (pa.partner_company_id is null) = coalesce(exclude_partner_company_ids, false)
        -- filled slice
        else not ((pa.partner_company_id = any(partner_company_ids)) = coalesce(exclude_partner_company_ids, false))
      end
    )
  )
  order by
    private.text_to_bigint(pa."number") asc
$$ language sql stable;

comment on function public.filter_partner_accounts is 'Filter `PartnerAccounts`.';
