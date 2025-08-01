-- currently used only for EU-OSS, but it can be generalized for future use
create table public.client_company_oss_branch (
  id uuid primary key default uuid_generate_v4(),

  client_company_id uuid not null references public.client_company(company_id) on delete cascade,

  country country_code not null,
  constraint unique_client_company_country unique (client_company_id, country),

  branch trimmed_text not null collate numeric,
  constraint unique_client_company_oss_branch unique (client_company_id, branch),

  general_ledger_account_id uuid not null references public.general_ledger_account(id) on delete restrict,

  invoice_accounting_item_title trimmed_text not null,

  created_by uuid not null
    default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
    references public.user(id) on delete set default,
  updated_by uuid references public.user(id) on delete set null,

  updated_at updated_time not null,
  created_at created_time not null
);

create index client_company_oss_branch_client_company_id_idx on public.client_company_oss_branch (client_company_id);
create index client_company_oss_branch_general_ledger_account_id_idx on public.client_company_oss_branch (general_ledger_account_id);
create index client_company_oss_branch_country_idx on public.client_company_oss_branch (country);

grant all on public.client_company_oss_branch to domonda_user;
grant select on public.invoice_accounting_item to domonda_wg_user;

----

create function public.create_client_company_oss_branch(
  client_company_id uuid,
  country country_code,
  branch trimmed_text,
  general_ledger_account_id uuid,
  invoice_accounting_item_title trimmed_text
) returns public.client_company_oss_branch as $$
  insert into public.client_company_oss_branch (
    client_company_id,
    country,
    branch,
    general_ledger_account_id,
    invoice_accounting_item_title,
    created_by
  ) values (
    create_client_company_oss_branch.client_company_id,
    create_client_company_oss_branch.country,
    create_client_company_oss_branch.branch,
    create_client_company_oss_branch.general_ledger_account_id,
    create_client_company_oss_branch.invoice_accounting_item_title,
    private.current_user_id()
  ) returning *
$$ language sql volatile strict;

create function public.update_client_company_oss_branch(
  id uuid,
  country country_code,
  branch trimmed_text,
  general_ledger_account_id uuid,
  invoice_accounting_item_title trimmed_text
) returns public.client_company_oss_branch as $$
  update public.client_company_oss_branch
  set
    country=update_client_company_oss_branch.country,
    branch=update_client_company_oss_branch.branch,
    general_ledger_account_id=update_client_company_oss_branch.general_ledger_account_id,
    invoice_accounting_item_title=update_client_company_oss_branch.invoice_accounting_item_title,
    updated_by=private.current_user_id(),
    updated_at=now()
  where id = update_client_company_oss_branch.id
  returning *
$$ language sql volatile strict;

create function public.delete_client_company_oss_branch(
  id uuid
) returns public.client_company_oss_branch as $$
  delete from public.client_company_oss_branch
  where id = delete_client_company_oss_branch.id
  returning *
$$ language sql volatile strict;

----

create function public.filter_client_company_oss_branches(
  client_company_id uuid,
  search_text       text = null
) returns setof public.client_company_oss_branch as $$
  select client_company_oss_branch.* from public.client_company_oss_branch
    inner join public.general_ledger_account on client_company_oss_branch.general_ledger_account_id = general_ledger_account.id
  where client_company_oss_branch.client_company_id = filter_client_company_oss_branches.client_company_id
  and (
    coalesce(trim(filter_client_company_oss_branches.search_text), '') = ''
    or (
      branch ilike '%'||filter_client_company_oss_branches.search_text||'%'
      or invoice_accounting_item_title ilike '%'||filter_client_company_oss_branches.search_text||'%'
      or general_ledger_account."number" ilike filter_client_company_oss_branches.search_text || '%'
      or general_ledger_account.name ilike '%' || filter_client_company_oss_branches.search_text || '%'
      or general_ledger_account.category ilike '%' || filter_client_company_oss_branches.search_text || '%'
    )
  )
  order by branch asc
$$ language sql stable;
