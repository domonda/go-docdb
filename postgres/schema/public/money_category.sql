create table public.money_category (
  id uuid primary key default uuid_generate_v4(),

  client_company_id         uuid not null references public.client_company(company_id) on delete cascade,
  general_ledger_account_id uuid references public.general_ledger_account(id) on delete restrict,

  name non_empty_text not null,

  -- TODO-db-210118 a special matching algorithm that would automatically
  -- categorise incoming transactions following a custom set of rules
  -- set up by the user. see related asana ticket for more info
  keywords trimmed_text[],
  updated_at updated_time not null,
  created_at created_time not null
);

create unique index money_category_client_company_id_name_unique on public.money_category(client_company_id, name);
create        index money_category_client_company_id_idx         on public.money_category(client_company_id);
create        index money_category_general_ledger_account_id_idx on public.money_category(general_ledger_account_id);

grant all on table public.money_category to domonda_user;

----

create function public.filter_money_categories(
  client_company_id uuid,
  search_text       text = null
) returns setof public.money_category as $$
  select money_category.*
  from public.money_category
    left join public.general_ledger_account on general_ledger_account.id = money_category.general_ledger_account_id
  where filter_money_categories.client_company_id = money_category.client_company_id
    and (coalesce(trim(search_text), '') = ''
      or money_category.name ilike '%' || search_text || '%'
      or general_ledger_account.number ilike '%' || search_text || '%'
      or general_ledger_account.name ilike '%' || search_text || '%'
      or general_ledger_account.category ilike '%' || search_text || '%'
    )
  order by name asc
$$ language sql stable;

----

create function public.create_money_category(
  client_company_id         uuid,
  name                      text,
  keywords                  trimmed_text[],
  general_ledger_account_id uuid = null
) returns public.money_category as $$
  insert into public.money_category(
    client_company_id,
    name,
    keywords,
    general_ledger_account_id
  ) values (
    create_money_category.client_company_id,
    create_money_category.name,
    create_money_category.keywords,
    create_money_category.general_ledger_account_id
  )
  returning *
$$ language sql volatile;
comment on function public.create_money_category is '@notNull';

create function public.update_money_category(
  id                        uuid,
  client_company_id         uuid,
  name                      text,
  keywords                  trimmed_text[],
  general_ledger_account_id uuid = null
) returns public.money_category as $$
  update public.money_category set
    client_company_id=update_money_category.client_company_id,
    name=update_money_category.name,
    keywords=update_money_category.keywords,
    general_ledger_account_id=update_money_category.general_ledger_account_id,
    updated_at=now()
  where id = update_money_category.id
  returning *
$$ language sql volatile;
comment on function public.update_money_category is '@notNull';

create function public.delete_money_category(
  id uuid
) returns public.money_category as $$
  delete from public.money_category
  where id = delete_money_category.id
  returning *
$$ language sql volatile strict;
comment on function public.delete_money_category is '@notNull';

----

create function public.money_categories_by_ids(
  ids uuid[]
) returns setof public.money_category as $$
  select * from public.money_category where id = any(ids)
$$ language sql stable strict;

----

-- TODO-db-210118 drop trigger once we allow the user to set their own money categories up
create function private.auto_create_money_categories_on_client_company_insert() returns trigger as $$
declare
begin
  -- issue built-in categories only if none exist already
  if not exists (select from public.money_category where client_company_id = new.company_id) then
    insert into public.money_category (client_company_id, name)
      values
        (new.company_id, 'Kredit/Credit'),
        (new.company_id, 'Zahlungsdienstleister/Payment provider'),
        (new.company_id, 'Privat/Private'),
        (new.company_id, 'Spesen/Fee'),
        (new.company_id, 'Zinsen/Interest'),
        (new.company_id, 'Übertrag/Transfer'),
        (new.company_id, 'Gehälter/Payroll'),
        (new.company_id, 'Abgaben/Taxes');
  end if;
  return new;
end
$$ language plpgsql;

create trigger auto_create_money_categories_on_client_company_insert_trigger
    after insert on public.client_company
    for each row
    execute function private.auto_create_money_categories_on_client_company_insert();
