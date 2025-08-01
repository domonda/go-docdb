create function public.filter_bank_accounts(
  client_company_id uuid,
  search_text       text = null,
  active            boolean = null,
  ibans             text[] = null
) returns setof public.bank_account as $$
  select ba.* from public.bank_account as ba
    inner join public.bank as b on b.bic = ba.bank_bic
  where ba.client_company_id = filter_bank_accounts.client_company_id
  and (
    coalesce(trim(filter_bank_accounts.search_text), '') = ''
    or (
      ba.name ilike '%' || filter_bank_accounts.search_text || '%'
      or b.legal_name ilike '%' || filter_bank_accounts.search_text || '%'
      or b.brand_name ilike '%' || filter_bank_accounts.search_text || '%'
      or ba.iban ilike '%' || filter_bank_accounts.search_text || '%'
      or b.bic ilike '%' || filter_bank_accounts.search_text || '%'
    )
  ) and (
    filter_bank_accounts.active is null
    or ba.active = filter_bank_accounts.active
  ) and (
    filter_bank_accounts.ibans is null
    or ba.iban = any(filter_bank_accounts.ibans)
  )
  order by ba.active desc
$$ language sql stable;
