create function public.filter_general_ledger_accounts(
  client_company_id uuid,
  search_text       text = null,
  active            boolean = null,
  has_real_estate_object_with_id uuid = null
) returns setof public.general_ledger_account as $$
  select general_ledger_account.* from public.general_ledger_account
    left join public.general_ledger_account_has_real_estate_object_by_id(general_ledger_account, has_real_estate_object_with_id) as has_real_estate_object on true
  where general_ledger_account.client_company_id = filter_general_ledger_accounts.client_company_id
  and (
    coalesce(trim(filter_general_ledger_accounts.search_text), '') = ''
    or (
      general_ledger_account."number" ilike filter_general_ledger_accounts.search_text || '%'
      or general_ledger_account.name ilike '%' || filter_general_ledger_accounts.search_text || '%'
      or general_ledger_account.category ilike '%' || filter_general_ledger_accounts.search_text || '%'
    )
  ) and (
    filter_general_ledger_accounts.active is null
    or (general_ledger_account.disabled_at is null) = filter_general_ledger_accounts.active
  )
  order by
    has_real_estate_object desc, -- first has, then doesnt have
    public.general_ledger_account_number_as_number(general_ledger_account)
$$ language sql stable;

comment on function public.filter_general_ledger_accounts is 'Filter `GeneralLedgerAccounts`.';
