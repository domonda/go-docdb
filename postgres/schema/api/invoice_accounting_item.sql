create view api.invoice_accounting_item with (security_barrier) as
    select
        iai.id,
        iai.invoice_document_id,
        iai.general_ledger_account_id,
        iai.title,
        iai.booking_type,
        iai.amount_type,
        iai.amount,
        iai.value_added_tax_id,
        iai.value_added_tax_percentage_id,
        iai.updated_by,
        iai.created_by,
        iai.updated_at,
        iai.created_at
    from public.invoice_accounting_item as iai
        join public.document as d on d.id = iai.invoice_document_id
    where d.client_company_id = (select api.current_client_company_id());

grant select on table api.invoice_accounting_item to domonda_api;

comment on column api.invoice_accounting_item.title is '@notNull';
comment on column api.invoice_accounting_item.booking_type is '@notNull';
comment on column api.invoice_accounting_item.amount_type is '@notNull';
comment on column api.invoice_accounting_item.amount is '@notNull';
comment on column api.invoice_accounting_item.updated_at is '@notNull';
comment on column api.invoice_accounting_item.created_at is '@notNull';
comment on view   api.invoice_accounting_item is $$
@primaryKey id
@foreignKey (invoice_document_id) references api.invoice (document_id)
@foreignKey (general_ledger_account_id) references api.general_ledger_account (id)
@foreignKey (updated_by) references api.user (id)
@foreignKey (created_by) references api.user (id)
A `InvoiceAccountingItem` represent a booking line for an `Invoice`.$$;

----

create function api.invoice_accounting_item_general_ledger_account_number(
  api_item api.invoice_accounting_item
) returns account_no as $$
  select "number" from public.general_ledger_account
  where id = api_item.general_ledger_account_id
$$ language sql stable strict
security definer; -- in order to use access the public schema

create function api.invoice_accounting_item_vat_percent(
  api_item api.invoice_accounting_item
) returns float8 as $$
  select "percentage" from public.value_added_tax_percentage
  where id = api_item.value_added_tax_percentage_id
$$ language sql stable strict
security definer; -- in order to use access the public schema

create function api.invoice_accounting_item_vat_introduced_at(
  api_item api.invoice_accounting_item
) returns date as $$
  select introduced_at from public.value_added_tax
  where id = api_item.value_added_tax_id
$$ language sql stable strict
security definer; -- in order to use access the public schema

create function api.invoice_accounting_item_vat_expired_at(
  api_item api.invoice_accounting_item
) returns date as $$
  select expired_at from public.value_added_tax
  where id = api_item.value_added_tax_id
$$ language sql stable strict
security definer; -- in order to use access the public schema

create function api.invoice_accounting_item_vat_type(
  api_item api.invoice_accounting_item
) returns public.value_added_tax_type as $$
  select "type" from public.value_added_tax
  where id = api_item.value_added_tax_id
$$ language sql stable strict
security definer; -- in order to use access the public schema

create function api.invoice_accounting_item_vat_name(
  api_item api.invoice_accounting_item
) returns text as $$
  select "name" from public.value_added_tax
  where id = api_item.value_added_tax_id
$$ language sql stable strict
security definer; -- in order to use access the public schema

create function api.invoice_accounting_item_vat_short_name(
  api_item api.invoice_accounting_item
) returns text as $$
  select short_name from public.value_added_tax
  where id = api_item.value_added_tax_id
$$ language sql stable strict
security definer; -- in order to use access the public schema

create function api.invoice_accounting_item_vat_net_only_amount(
  api_item api.invoice_accounting_item
) returns boolean as $$
  select net_only_amount from public.value_added_tax
  where id = api_item.value_added_tax_id
$$ language sql stable strict
security definer; -- in order to use access the public schema

create function api.invoice_accounting_item_vat_vatid_required(
  api_item api.invoice_accounting_item
) returns boolean as $$
  select vat_id_required from public.value_added_tax
  where id = api_item.value_added_tax_id
$$ language sql stable strict
security definer; -- in order to use access the public schema

create function api.invoice_accounting_item_vat_country(
  api_item api.invoice_accounting_item
) returns country_code as $$
  select country from public.value_added_tax
  where id = api_item.value_added_tax_id
$$ language sql stable strict
security definer; -- in order to use access the public schema

create function api.invoice_accounting_item_net_amount(
  api_item api.invoice_accounting_item
) returns float8 as
$$
  select public.invoice_accounting_item_net(public_item)
  from public.invoice_accounting_item as public_item
  where public_item.id = api_item.id
$$ language sql stable strict
security definer; -- in order to use access the public schema


create function api.invoice_accounting_item_tax_amount(
  api_item api.invoice_accounting_item
) returns float8 as $$
  select public.invoice_accounting_item_tax(public_item)
  from public.invoice_accounting_item as public_item
  where public_item.id = api_item.id
$$ language sql stable strict
security definer; -- in order to use access the public schema


create function api.invoice_accounting_item_total_amount(
  api_item api.invoice_accounting_item
) returns float8 as $$
  select public.invoice_accounting_item_total(public_item)
  from public.invoice_accounting_item as public_item
  where public_item.id = api_item.id
$$ language sql stable strict
security definer; -- in order to use access the public schema


create function api.invoice_accounting_item_partner_account_number(
  api_item api.invoice_accounting_item
) returns text as $$
  select public.invoice_accounting_item_partner_account_number(public_item)
  from public.invoice_accounting_item as public_item
  where public_item.id = api_item.id
$$ language sql stable strict
security definer; -- in order to use access the public schema


create function api.invoice_accounting_item_debit_account_number(
  api_item api.invoice_accounting_item
) returns text as $$
  select public.invoice_accounting_item_debit_account_number(public_item)
  from public.invoice_accounting_item as public_item
  where public_item.id = api_item.id
$$ language sql stable strict
security definer; -- in order to use access the public schema


create function api.invoice_accounting_item_credit_account_number(
  api_item api.invoice_accounting_item
) returns text as $$
  select public.invoice_accounting_item_credit_account_number(public_item)
  from public.invoice_accounting_item as public_item
  where public_item.id = api_item.id
$$ language sql stable strict
security definer; -- in order to use access the public schema


create function api.invoice_accounting_item_vat_code(
  api_item api.invoice_accounting_item
) returns text as $$
  select (public.invoice_accounting_item_value_added_tax_code(public_item)).code
  from public.invoice_accounting_item as public_item
  where public_item.id = api_item.id
$$ language sql stable strict
security definer; -- in order to use access the public schema


create function api.invoice_accounting_item_vat_reclaimable(
  api_item api.invoice_accounting_item
) returns boolean as $$
  select (public.invoice_accounting_item_value_added_tax_code(public_item)).reclaimable
  from public.invoice_accounting_item as public_item
  where public_item.id = api_item.id
$$ language sql stable strict
security definer; -- in order to use access the public schema

