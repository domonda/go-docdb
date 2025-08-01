create function public.filter_cash_accounts(
  client_company_id uuid,
  search_text       text = null,
  active            boolean = null
) returns setof public.cash_account as $$
  select * from public.cash_account
  where client_company_id = filter_cash_accounts.client_company_id
  and ((coalesce(trim(filter_cash_accounts.search_text), '') = '')
    or (
      ("number" ilike '%' || filter_cash_accounts.search_text || '%')
      or (name ilike '%' || filter_cash_accounts.search_text || '%')))
  and (filter_cash_accounts.active is null
    or (active = filter_cash_accounts.active))
  order by
    active desc,
    name desc,
    "number" desc
$$ language sql stable;
