create function public.filter_value_added_taxes(
  client_company_id uuid,
  search_text       text = null,
  "type"            public.value_added_tax_type = null,
  country           country_code = null
) returns setof public.value_added_tax as $$
  with company as (
    select cc.company_id, cc.tax_reclaimable, cc.accounting_system, cl.country
    from public.client_company as cc
      inner join public.company as c on c.id = cc.company_id
      inner join public.company_location as cl on cl.company_id = c.id and cl.main
    where cc.company_id = filter_value_added_taxes.client_company_id
  ), filtered_vat as (
    select v.* from public.value_added_tax as v, company as c
    where exists (
      select from public.value_added_tax_code as vc
      where (
        vc.value_added_tax_id = v.id
        or vc.value_added_tax_percentage_id in (
          select id from public.value_added_tax_percentage as vp
          where vp.value_added_tax_id = v.id
        )
      ) and vc.reclaimable = c.tax_reclaimable
      and vc.accounting_system = public.vat_accounting_system(c.accounting_system)
      and (vc.client_company_id is null or vc.client_company_id = c.company_id)
      and (
        case when filter_value_added_taxes.country is not null then
          v.country = filter_value_added_taxes.country
        else
          v.country = c.country
        end
      )
    )
  ), fallback_vat as (
    select v.* from public.value_added_tax as v, company as c
    where v.id in (
      '66e9bce0-55aa-45a6-b388-03f885772cff', -- AT	Vorsteuer
      '52475137-cb50-403e-bc31-3cf3ae079129', -- AT	Umsatzsteuer
      '649927ac-81c8-4680-89f2-0a3033f19546', -- DE	Vorsteuer
      '268bea24-0add-4213-a70c-3010f10e4ec9'  -- DE	Umsatzsteuer
    ) and exists (
      select from public.value_added_tax_code as vc
      where vc.value_added_tax_id = v.id
      and vc.reclaimable = c.tax_reclaimable
    ) and (
      case when filter_value_added_taxes.country is not null then
        v.country = filter_value_added_taxes.country
      else
        v.country = c.country
      end
    )
  )
  select v.* from (
    select * from filtered_vat
    union all
    select * from fallback_vat where not exists (select from filtered_vat)
  ) as v
  left join lateral (
    select * from public.value_added_tax_code
    where value_added_tax_code.value_added_tax_id = v.id
    and value_added_tax_code.code ilike '%' || filter_value_added_taxes.search_text || '%'
    limit 1
  ) as vatc_match on true
  where (
    filter_value_added_taxes.type is null or v.type = filter_value_added_taxes.type
  ) and (
    filter_value_added_taxes.search_text is null
    or (
      v.name ilike '%' || filter_value_added_taxes.search_text || '%'
      or v.short_name ilike '%' || filter_value_added_taxes.search_text || '%'
      or not (vatc_match is null)
    )
  )
  order by vatc_match is null, v.index desc, v.short_name
$$ language sql stable;
