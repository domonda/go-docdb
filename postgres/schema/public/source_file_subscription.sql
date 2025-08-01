create trigger gql_source_file_updated
  after update on public.source_file
  for each row
  execute procedure private.gql_subscription(
    'sourceFileUpdated', -- event
    'sourceFileUpdated:$1', -- topic
    'id' -- subjects
  );

create trigger gql_source_file_money_transactions_import_destination_updated
  after update on public.source_file_money_transactions
  for each row
  when (old.import_destination_bank_account_id is distinct from new.import_destination_bank_account_id
    or old.import_destination_credit_card_account_id is distinct from new.import_destination_credit_card_account_id)
  execute procedure private.gql_subscription(
    'sourceFileUpdated', -- event
    'sourceFileUpdated:$1', -- topic
    'source_file_id' -- subjects
  );

create trigger gql_source_file_money_transactions_created_deleted
  after insert or delete on public.source_file_money_transactions
  for each row
  execute procedure private.gql_subscription(
    'sourceFileUpdated', -- event
    'sourceFileUpdated:$1', -- topic
    'source_file_id' -- subjects
  );
