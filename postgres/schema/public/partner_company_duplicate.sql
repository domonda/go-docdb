create type public.partner_company_duplicate_reason as enum (
  'VAT_ID',
  'EMAIL',
  'IBAN',
  'SAME_NAME',
  'SIMILAR_NAME'
);

create type public.partner_company_duplicate as (
  partner_company_location_id uuid,
  duplicate_partner_company_id uuid,
  duplicate_company_location_id uuid,
  reason public.partner_company_duplicate_reason,
  value trimmed_text
);

comment on column public.partner_company_duplicate.partner_company_location_id is 'The location considered as a duplicate from the originating `PartnerCompany`. If null, the duplicate is not related to a `CompanyLocation`.';
comment on column public.partner_company_duplicate.duplicate_partner_company_id is 'If null, the duplicate is the originating `ClientCompany`; otherwise, a specific `PartnerCompany` within.';
comment on column public.partner_company_duplicate.duplicate_company_location_id is 'The location considered as a duplicate from the destination/duplicate `PartnerCompany`. If null, the duplicate is not related to a `CompanyLocation`.';
comment on column public.partner_company_duplicate.reason is '@notNull';
comment on column public.partner_company_duplicate.value is E'@notNull\nThe value that is detected as a duplicate.';
comment on type public.partner_company_duplicate is $$
@foreignKey (partner_company_location_id) references public.company_location (id)
@foreignKey (duplicate_partner_company_id) references public.partner_company (id)
@foreignKey (duplicate_company_location_id) references public.company_location (id)
$$;

-- NOTE: highly inaccurate
create function public.similar_name_partner_companies(
  name trimmed_text
) returns setof public.partner_company as $$
  select *
  from public.partner_company
  where word_similarity(partner_company.derived_name, similar_name_partner_companies.name) >= 0.8
$$ language sql stable;

create function public.partner_company_duplicate_partner_companies(
  partner_company public.partner_company
) returns setof public.partner_company_duplicate as $$
  with partner_location as (
    select * from public.company_location
    where company_location.partner_company_id = partner_company.id
    or company_location.company_id = partner_company.company_id
  )
  (
    select
      partner_location.id,
      null,
      duplicate_location.id,
      'VAT_ID'::public.partner_company_duplicate_reason,
      duplicate_location.vat_id_no::trimmed_text
    from partner_location
      inner join public.company_location as duplicate_location
      on duplicate_location.company_id = partner_company.client_company_id
    where partner_location.vat_id_no = duplicate_location.vat_id_no
  ) union all (
    select
      partner_location.id,
      duplicate_partner.id,
      duplicate_location.id,
      'VAT_ID'::public.partner_company_duplicate_reason,
      duplicate_location.vat_id_no::trimmed_text
    from partner_location
      inner join (public.partner_company as duplicate_partner
        inner join public.company_location as duplicate_location
          on duplicate_location.partner_company_id = duplicate_partner.id
          or duplicate_location.company_id = duplicate_partner.company_id)
        on partner_company.id <> duplicate_partner.id
        and partner_company.client_company_id = duplicate_partner.client_company_id
    where partner_location.vat_id_no = duplicate_location.vat_id_no
  ) union all (
    select
      partner_location.id,
      null,
      duplicate_location.id,
      'EMAIL'::public.partner_company_duplicate_reason,
      duplicate_location.email::trimmed_text
    from partner_location
      inner join public.company_location as duplicate_location
      on duplicate_location.company_id = partner_company.client_company_id
    where partner_location.email = duplicate_location.email
  ) union all (
    select
      partner_location.id,
      duplicate_partner.id,
      duplicate_location.id,
      'EMAIL'::public.partner_company_duplicate_reason,
      duplicate_location.email::trimmed_text
    from partner_location
      inner join (public.partner_company as duplicate_partner
        inner join public.company_location as duplicate_location
          on duplicate_location.partner_company_id = duplicate_partner.id
          or duplicate_location.company_id = duplicate_partner.company_id)
        on partner_company.id <> duplicate_partner.id
        and partner_company.client_company_id = duplicate_partner.client_company_id
    where partner_location.email = duplicate_location.email
    and (
      -- different and not-null VAT-IDs means that the locations are indeed different
      -- p.s. we dont need to check here for same VAT-IDs because thats a different check
      partner_location.vat_id_no is null
      or duplicate_location.vat_id_no is null
    )
  ) union all (
    select
      null,
      duplicate_partner.id,
      null,
      'SAME_NAME'::public.partner_company_duplicate_reason,
      duplicate_partner.derived_name
    from public.partner_company as duplicate_partner
    where partner_company.id <> duplicate_partner.id
    and partner_company.client_company_id = duplicate_partner.client_company_id
    and partner_company.derived_name = duplicate_partner.derived_name
  -- TODO: highly inaccurate
  -- ) union all (
  --   select
  --     null,
  --     null,
  --     null,
  --     'SIMILAR_NAME'::public.partner_company_duplicate_reason,
  --     trim(public.company_brand_name_or_name(company))::trimmed_text
  --   from public.company
  --   where company.id = partner_company.client_company_id
  --   and word_similarity(partner_company.derived_name, public.company_brand_name_or_name(company)) >= 0.8
  -- ) union all (
  --   select
  --     null,
  --     duplicate_partner.id,
  --     null,
  --     'SIMILAR_NAME'::public.partner_company_duplicate_reason,
  --     duplicate_partner.derived_name
  --   from public.similar_name_partner_companies(partner_company.derived_name) as duplicate_partner
  --   where partner_company.client_company_id = duplicate_partner.client_company_id
  --   and partner_company.id <> duplicate_partner.id
  -- TODO:
  -- ) union all (
  --   select null, 'IBAN'::public.partner_company_duplicate_reason
  -- ) union all (
  --   select duplicate_partner.id, 'IBAN'::public.partner_company_duplicate_reason
  )
$$ language sql stable;
