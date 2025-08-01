create type public.filter_partner_companies_order_by AS ENUM (
  'CREATED_AT_ASC',
  'CREATED_AT_DESC'
);

create function public.filter_partner_companies(
    client_company_id uuid,
    search_text       text = null,
    order_by          public.filter_partner_companies_order_by = null,
    with_duplicates   boolean = false,
    active            boolean = null
) returns setof public.partner_company as
$$
    select pc.* from public.partner_company as pc
        left join public.company as c on (c.id = pc.company_id)
    where (
        pc.client_company_id = filter_partner_companies.client_company_id
    ) and (
        (coalesce(trim(search_text), '') = '') or (
            (
                pc.name ilike '%' || search_text || '%'
            ) or (
                c.name ilike '%' || search_text || '%'
            ) or (
                c.brand_name ilike '%' || search_text || '%'
            ) or (
                -- TODO-db-201027 check performance of this
                exists (select from public.partner_company_locations(pc) as company_location
                    where company_location.vat_id_no ilike '%' || search_text || '%')
            ) or (
                exists (select from public.partner_account
                    where partner_account.partner_company_id = pc.id
                    and (partner_account.number ilike '%' || search_text || '%'
                        or partner_account.description ilike '%' || search_text || '%'))
            )
        )
    ) and (
        not with_duplicates
        or exists (
            select from public.partner_company_duplicate_partner_companies(pc)
        )
    ) and (
        filter_partner_companies.active is null
        or (pc.disabled_at is null) = filter_partner_companies.active
    )
    order by
    -- when search_text exists, order by exact name match and then by name length
    case
        when coalesce(trim(search_text), '') <> '' and pc.name ilike search_text then 0
        when coalesce(trim(search_text), '') <> '' and c.name ilike search_text then 0
        when coalesce(trim(search_text), '') <> '' and c.brand_name ilike search_text then 0
        else 1
    end,
    case when coalesce(trim(search_text), '') <> '' then length(coalesce(pc.name, c.brand_name, c.name)) end,
    case when order_by = 'CREATED_AT_ASC' then pc.created_at end asc,
    case when order_by = 'CREATED_AT_DESC' then pc.created_at end desc,
    coalesce(pc.name, c.brand_name, c.name)
$$
language sql stable;

comment on function public.filter_partner_companies is 'Filters `PartnerCompanies`.';
