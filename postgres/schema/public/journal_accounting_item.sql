create table public.journal_accounting_item (
  id uuid primary key default uuid_generate_v4(),

  partner_account_id        uuid not null references public.partner_account(id) on delete cascade,
  general_ledger_account_id uuid not null references public.general_ledger_account(id) on delete cascade,

  title non_empty_text not null, -- TODO change to trimmed_text

  value_added_tax_id            uuid references public.value_added_tax(id) on delete restrict,
  value_added_tax_percentage_id uuid references public.value_added_tax_percentage(id) on delete restrict,

  -- when the percentage is set, the vat must be as well
  constraint percentage_and_vat_check check((value_added_tax_percentage_id is null) or (value_added_tax_id is not null)),

  updated_at updated_time not null,
  created_at created_time not null
);

create index journal_accounting_item_partner_account_id_idx on public.journal_accounting_item (partner_account_id);
create index journal_accounting_item_general_ledger_account_id_idx on public.journal_accounting_item (general_ledger_account_id);
create index journal_accounting_item_value_added_tax_id_idx on public.journal_accounting_item (value_added_tax_id);
create index journal_accounting_item_value_added_tax_percentage_id_idx on public.journal_accounting_item (value_added_tax_percentage_id);

grant select on public.journal_accounting_item to domonda_user;
