create trigger gql_review_group_created
  after insert on public.review_group
  for each row
  execute procedure private.gql_subscription(
    'reviewGroupCreated', -- event
    'reviewGroupCreated:$2', -- topic
    'id', 'client_company_id' -- subjects
  );

create trigger gql_review_group_created_in
  after insert on public.review_group
  for each row
  execute procedure private.gql_subscription(
    'reviewGroupCreatedIn', -- event
    'reviewGroupCreatedIn:$3', -- topic
    'id', 'created_by', 'client_company_id', 'origin' -- subjects
  );

create trigger gql_review_group_updated
  after update on public.review_group
  for each row
  execute procedure private.gql_subscription(
    'reviewGroupUpdated', -- event
    'reviewGroupUpdated:$1', -- topic
    'id' -- subjects
  );

create trigger gql_review_group_updated_documents_changed
  after insert or delete on public.review_group_document
  for each row
  execute procedure private.gql_subscription(
    'reviewGroupUpdated', -- event
    'reviewGroupUpdated:$1', -- topic
    'review_group_id' -- subjects
  );
