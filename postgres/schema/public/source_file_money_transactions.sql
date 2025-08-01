create type public.source_file_money_transactions_type as enum (
  'BANK',
  'CREDIT_CARD'
);

create table public.source_file_money_transactions (
  source_file_id uuid primary key references public.source_file(id) on delete cascade,

  "type"                   public.source_file_money_transactions_type not null,
  bank_transactions        public.bank_transaction[],
  credit_card_transactions public.credit_card_transaction[],
  constraint money_transactions_type_check check(
    case "type"
      when 'BANK' then bank_transactions is not null
      when 'CREDIT_CARD' then credit_card_transactions is not null
      else false
    end
  ),

  -- when set, the user reviewed the import and set the destination
  import_destination_bank_account_id        uuid references public.bank_account(id) on delete set null,
  import_destination_credit_card_account_id uuid references public.credit_card_account(id) on delete set null,
  constraint import_destination_account_type_check check(
    -- you cannot set a destination account different from the type
    case "type"
      when 'BANK' then import_destination_credit_card_account_id is null
      when 'CREDIT_CARD' then import_destination_bank_account_id is null
      else false
    end
  ),

  updated_at updated_time not null,
  created_at created_time not null
);

grant select on public.source_file_money_transactions to domonda_user;
grant select on public.source_file_money_transactions to domonda_wg_user;

create index source_file_money_transactions_dest_bank_account_id_idx on public.source_file_money_transactions (import_destination_bank_account_id);
create index source_file_money_transactions_dest_credit_card_account_id_idx on public.source_file_money_transactions (import_destination_credit_card_account_id);
