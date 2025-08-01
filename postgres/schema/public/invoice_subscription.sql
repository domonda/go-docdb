create trigger gql_invoice_changed
  after update on public.invoice
  for each row
  execute procedure private.gql_subscription(
    'invoiceChanged', -- event
    'invoiceChanged:document_id=$1', -- topic
    'document_id' -- subjects
  );
