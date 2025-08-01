create function private.make_date_fulltext(d date)
returns text as $$
  select d::text || ' ' || to_char(d, 'DD.MM.YYYY')
$$ language sql immutable strict;


create function private.make_money_amount_fulltext(amount float8)
returns text as $$
  select amount::text || ' ' || public.format_money_german(amount) || ' ' || public.format_money_int(amount)
$$ language sql immutable strict;


create function private.make_document_fulltext(document public.document)
returns text as $$
declare
  fulltext text;
begin
  -- most important data for the fulltext column
  fulltext :=
    document.id || ' ' ||
    document.source_file || ' ' ||
    coalesce(document.title || ' ', '') ||
    coalesce(private.make_date_fulltext(document.import_date::date) || ' ', '') ||
    coalesce(private.real_estate_object_fulltext(public.document_real_estate_object(document)) || ' ', '') ||
    document.fulltext;
  -- remove double spaces and trim
  fulltext := trim(regexp_replace(fulltext, '\s+', ' ', 'g'));
  return fulltext;
end
$$ language plpgsql immutable strict;


create function private.make_invoice_fulltext(invoice public.invoice)
returns text as $$
declare
  fulltext text;
begin
  -- most important data for the fulltext column
  fulltext :=
    coalesce(public.invoice_partner_name(invoice) || ' ', '') ||
    coalesce(public.invoice_partner_vat_id_no(invoice) || ' ', '') ||
    coalesce(public.invoice_account_number(invoice) || ' ', '') ||
    coalesce(invoice.invoice_number || ' ', '') ||
    coalesce(invoice.order_number || ' ', '') ||
    coalesce(invoice.internal_number || ' ', '') ||
    coalesce(private.make_date_fulltext(invoice.invoice_date) || ' ', '') ||
    coalesce(private.make_date_fulltext(invoice.order_date) || ' ', '') ||
    invoice.currency || ' ' ||
    coalesce(private.make_money_amount_fulltext(invoice.net) || ' ', '') ||
    coalesce(private.make_money_amount_fulltext(invoice.total) || ' ', '') ||
    -- TODO idwell open_items_number, ger_clause_35a_net, ger_clause_35a_total
    -- coalesce(private.make_money_amount_fulltext(invoice.ger_clause_35a_net) || ' ', '') ||
    -- coalesce(private.make_money_amount_fulltext(invoice.ger_clause_35a_total) || ' ', '') ||
    -- coalesce(invoice.open_items_number || ' ', '') ||
    coalesce(invoice.iban || ' ', '') ||
    coalesce(invoice.bic, '');
  -- remove double spaces and trim
  fulltext := trim(regexp_replace(fulltext, '\s+', ' ', 'g'));
  return fulltext;
end
$$ language plpgsql stable strict;


create function private.make_deliverynote_fulltext(delivery_note public.delivery_note)
returns text as $$
declare
  fulltext text;
begin
  -- most important data for the fulltext column
  fulltext :=
    coalesce(delivery_note.invoice_number || ' ', '') ||
    coalesce(delivery_note.note_number || ' ', '') ||
    coalesce(private.make_date_fulltext(delivery_note.issue_date) || ' ', '') ||
    coalesce(private.make_date_fulltext(delivery_note.delivered_at::date) || ' ', '') ||
    coalesce(private.make_money_amount_fulltext(delivery_note.net_sum), '');
  -- remove double spaces and trim
  fulltext := trim(regexp_replace(fulltext, '\s+', ' ', 'g'));
  return fulltext;
end
$$ language plpgsql stable strict;


create function private.make_other_document_fulltext(other_document public.other_document)
returns text as $$
declare
  fulltext text;
begin
  -- most important data for the fulltext column
  fulltext :=
    coalesce(public.other_document_partner_name(other_document) || ' ', '') ||
    coalesce(other_document.document_number || ' ', '') ||
    coalesce(private.make_date_fulltext(other_document.document_date) || ' ', '') ||
    coalesce(private.make_date_fulltext(other_document.resubmission_date) || ' ', '') ||
    coalesce(private.make_date_fulltext(other_document.expiry_date) || ' ', '') ||
    coalesce(other_document.document_details, '');
  -- remove double spaces and trim
  fulltext := trim(regexp_replace(fulltext, '\s+', ' ', 'g'));
  return fulltext;
end
$$ language plpgsql stable strict;

----

create function private.document_update_fulltext_and_searchtext() returns trigger as $$
declare
  doc   public.document;
  inv   public.invoice;
  othr  public.other_document;
  dnote public.delivery_note;
begin
  case
    when tg_table_schema = 'public' and tg_table_name = 'document'
    then

      -- sanitize document fulltext
      new.fulltext_w_invoice := private.make_document_fulltext(new);

      -- prepend invoice sanitized fulltext if invoice exists
      select * into inv
      from public.invoice
      where invoice.document_id = new.id;
      if found then
        new.fulltext_w_invoice = private.make_invoice_fulltext(inv) || ' ' || new.fulltext_w_invoice;
      end if;

      -- prepend delivery note document sanitized fulltext if other document exists
      select * into dnote
      from public.delivery_note
      where delivery_note.document_id = new.id;
      if found then
        new.fulltext_w_invoice = private.make_deliverynote_fulltext(dnote) || ' ' || new.fulltext_w_invoice;
      end if;

      -- prepend other document sanitized fulltext if other document exists
      select * into othr
      from public.other_document
      where other_document.document_id = new.id;
      if found then
        new.fulltext_w_invoice = private.make_other_document_fulltext(othr) || ' ' || new.fulltext_w_invoice;
      end if;

      -- create searchtext
      new.searchtext := to_tsvector('german', left(new.fulltext_w_invoice, 1000000)); -- tsvector has a < 1MB length limit

      return new;

    when tg_table_schema = 'public' and tg_table_name in ('invoice', 'delivery_note', 'other_document', 'document_real_estate_object')
    then

      -- the update on public.document will cause this trigger function to be called for the document
      -- which will re-populate the fulltext columns as implemented above
      update public.document
      set fulltext_w_invoice=null, searchtext=null
      where document.id = new.document_id;

      return new;

    else
      raise exception 'Fulltext and searchtext update not implemented for table "%.%"', tg_table_schema, tg_table_name;
  end case;
end
$$ language plpgsql volatile strict;


create trigger document_update_fulltext_and_searchtext_insert
  before insert on public.document
  for each row
  execute procedure private.document_update_fulltext_and_searchtext();
create trigger document_update_fulltext_and_searchtext_update
  before update on public.document
  for each row
  when (
    old.id is distinct from new.id
      or old.client_company_id is distinct from new.client_company_id -- other client company might have other business partners
      or old.category_id is distinct from new.category_id
      or old.source_file is distinct from new.source_file
      or old.title is distinct from new.title
      or old.import_date is distinct from new.import_date
      or old.fulltext is distinct from new.fulltext
      or old.fulltext_w_invoice is distinct from new.fulltext_w_invoice
      or old.searchtext is distinct from new.searchtext
  )
  execute procedure private.document_update_fulltext_and_searchtext();


create trigger invoice_document_update_fulltext_and_searchtext_insert
  after insert on public.invoice
  for each row
  execute procedure private.document_update_fulltext_and_searchtext();
-- Delete trigger not needed because category_id change causes trigger too
-- create trigger invoice_document_update_fulltext_and_searchtext_delete
--   after delete on public.invoice
--   for each row
--   execute procedure private.document_update_fulltext_and_searchtext();
create trigger invoice_document_update_fulltext_and_searchtext_update
  after update on public.invoice
  for each row
  when (
    public.invoice_partner_name(old) is distinct from public.invoice_partner_name(new)
      or public.invoice_partner_vat_id_no(old) is distinct from public.invoice_partner_vat_id_no(new)
      or public.invoice_account_number(old) is distinct from public.invoice_account_number(new)
      or old.invoice_number is distinct from new.invoice_number
      or old.order_number is distinct from new.order_number
      or old.internal_number is distinct from new.internal_number
      or old.invoice_date is distinct from new.invoice_date
      or old.order_date is distinct from new.order_date
      or old.currency is distinct from new.currency
      or old.net is distinct from new.net
      or old.total is distinct from new.total
      -- TODO idwell open_items_number, ger_clause_35a_net, ger_clause_35a_total
      or old.iban is distinct from new.iban
      or old.bic is distinct from new.bic
  )
  execute procedure private.document_update_fulltext_and_searchtext();


create trigger other_document_document_update_fulltext_and_searchtext_insert
  after insert on public.other_document
  for each row
  execute procedure private.document_update_fulltext_and_searchtext();
-- Delete trigger not needed because category_id change causes trigger too
-- create trigger other_document_document_update_fulltext_and_searchtext_delete
--   after delete on public.other_document
--   for each row
--   execute procedure private.document_update_fulltext_and_searchtext();
create trigger other_document_document_update_fulltext_and_searchtext_update
  after update on public.other_document
  for each row
  when (
    public.other_document_partner_name(old) is distinct from public.other_document_partner_name(new)
      or old.document_number is distinct from new.document_number
      or old.document_date is distinct from new.document_date
      or old.resubmission_date is distinct from new.resubmission_date
      or old.expiry_date is distinct from new.expiry_date
      or old.document_details is distinct from new.document_details
  )
  execute procedure private.document_update_fulltext_and_searchtext();


create trigger delivery_note_document_update_fulltext_and_searchtext_insert
  after insert on public.delivery_note
  for each row
  execute procedure private.document_update_fulltext_and_searchtext();
-- Delete trigger not needed because category_id change causes trigger too
-- create trigger delivery_note_document_update_fulltext_and_searchtext_delete
--   after delete on public.delivery_note
--   for each row
--   execute procedure private.document_update_fulltext_and_searchtext();
create trigger delivery_note_document_update_fulltext_and_searchtext_update
  after update on public.delivery_note
  for each row
  when (
    old.note_number is distinct from new.note_number
      or old.invoice_number is distinct from new.invoice_number
  )
  execute procedure private.document_update_fulltext_and_searchtext();
