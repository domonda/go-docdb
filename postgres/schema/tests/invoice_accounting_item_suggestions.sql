\echo
\echo '=== schema/tests/invoice_accounting_item_suggestions_tests.sql ==='
\echo

---- Double-entry bookkeeping ----
-- DEBIT = money coming in (+)
-- CREDIT = money going out (-)
-- VENDOR <-> DEBIT
-- CLIENT <-> CREDIT

-- we prefix the functions with "t_" to avoid mixing in with existing functions

create function t_client_company_id()
returns uuid as $$
  select 'fc723c5c-ea2c-4399-917e-535c4f047a1b'::uuid
$$ language sql immutable;

-- prepare test client
insert into public.company (id, name, legal_form)
  values (t_client_company_id(), 'Testomonda', 'GMBH');
insert into public.client_company (company_id, accounting_company_client_company_id, email_alias)
  values (t_client_company_id(), 'c1fd6da0-e1e5-4607-bc92-885339a37649', 'testomonda');
insert into public.company_location (company_id, main, country)
  values (t_client_company_id(), true, 'AT');

create function t_set_client_company(
  country country_code,
  tax_reclaimable boolean
) returns void as $$
begin
  update public.company_location
  set country=t_set_client_company.country
  where company_id = t_client_company_id()
  and main;

  update public.client_company
  set tax_reclaimable=t_set_client_company.tax_reclaimable
  where company_id = t_client_company_id();
end
$$ language plpgsql volatile;

create function t_create_partner(
  name text,
  vendor_number account_no,
  client_number account_no
) returns uuid as $$
  with new_partner_company as (
    insert into public.partner_company (client_company_id, name)
    values (t_client_company_id(), t_create_partner.name)
    returning id
  )
  insert into public.partner_account (client_company_id, partner_company_id, "type", "number")
  values
    (t_client_company_id(), (select id from new_partner_company), 'VENDOR', t_create_partner.vendor_number),
    (t_client_company_id(), (select id from new_partner_company), 'CLIENT', t_create_partner.client_number)
  returning partner_company_id
$$ language sql volatile strict;

create function t_account_from_partner(
  partner_company_id uuid,
  "type" public.partner_account_type
) returns uuid as $$
  select id from public.partner_account
  where partner_account.partner_company_id = t_account_from_partner.partner_company_id
  and "type" = t_account_from_partner."type"
$$ language sql stable strict;

create function t_create_general_ledger_account(
  name text,
  "number" account_no
) returns uuid as $$
  insert into public.general_ledger_account (client_company_id, name, "number")
  values (t_client_company_id(), t_create_general_ledger_account.name, t_create_general_ledger_account."number")
  returning id
$$ language sql volatile strict;

create temp sequence t_created_accounting_items;
create function t_create_accounting_item(
  partner_account_id uuid,
  general_ledger_account_id uuid,
  title non_empty_text,
  value_added_tax_id uuid = null,
  value_added_tax_percentage_id uuid = null
) returns uuid as $$
declare
  time_offset bigint := nextval('t_created_accounting_items');
  created_accounting_item_id uuid;
begin
  insert into public.journal_accounting_item (partner_account_id, general_ledger_account_id, title, value_added_tax_id, value_added_tax_percentage_id, updated_at, created_at)
  values (
    t_create_accounting_item.partner_account_id,
    t_create_accounting_item.general_ledger_account_id,
    t_create_accounting_item.title,
    t_create_accounting_item.value_added_tax_id,
    t_create_accounting_item.value_added_tax_percentage_id,
    -- we offset the times to match the insert order with the age (all now()s in a transaction have the same time)
    now() + (time_offset * interval '1 second'),
    now() + (time_offset * interval '1 second')
  )
  returning id into created_accounting_item_id;

  return created_accounting_item_id;
end
$$ language plpgsql volatile;

create type t_value_added_tax_and_percentage as (
  value_added_tax_id uuid,
  value_added_tax_percentage_id uuid
);
create function t_get_value_added_tax_and_percentage(
  percentage float8,
  net_only boolean = false
) returns t_value_added_tax_and_percentage as $$
declare
  result t_value_added_tax_and_percentage;
begin
  select
    value_added_tax.id,
    value_added_tax_percentage.id
  into result
  from public.value_added_tax
    -- not all VATs have percentages
    inner join public.value_added_tax_percentage on value_added_tax_percentage.value_added_tax_id = value_added_tax.id
  where value_added_tax_percentage.percentage = t_get_value_added_tax_and_percentage.percentage
  and value_added_tax.net_only_amount = t_get_value_added_tax_and_percentage.net_only
  order by value_added_tax_percentage.id
  limit 1;

  if result is null then
    raise exception 'Could not find VAT with % %%', percentage;
  end if;

  return result;
end
$$ language plpgsql stable strict;

create function t_expect_accounting_item(
  -- actual
  accounting_item public.invoice_accounting_item,
  -- expect
  general_ledger_account_id uuid,
  title text,
  booking_type public.invoice_accounting_item_booking_type,
  amount_type public.invoice_accounting_item_amount_type,
  amount float8,
  value_added_tax_id uuid = null,
  value_added_tax_percentage_id uuid = null
) returns void as $$
declare
  failing boolean;
begin
  if accounting_item.general_ledger_account_id is distinct from t_expect_accounting_item.general_ledger_account_id
  then
    failing := true;
    raise notice 'Different general_ledger_account_id - expected "%", got "%"', t_expect_accounting_item.general_ledger_account_id, accounting_item.general_ledger_account_id;
  end if;

  if accounting_item.title is distinct from t_expect_accounting_item.title
  then
    failing := true;
    raise notice 'Different title - expected "%", got "%"', t_expect_accounting_item.title, accounting_item.title;
  end if;

  if accounting_item.booking_type is distinct from t_expect_accounting_item.booking_type
  then
    failing := true;
    raise notice 'Different booking_type - expected "%", got "%"', t_expect_accounting_item.booking_type, accounting_item.booking_type;
  end if;

  if accounting_item.amount_type is distinct from t_expect_accounting_item.amount_type
  then
    failing := true;
    raise notice 'Different amount_type - expected "%", got "%"', t_expect_accounting_item.amount_type, accounting_item.amount_type;
  end if;

  if accounting_item.amount is distinct from t_expect_accounting_item.amount
  then
    failing := true;
    raise notice 'Different amount - expected "%", got "%"', t_expect_accounting_item.amount, accounting_item.amount;
  end if;

  if accounting_item.value_added_tax_id is distinct from t_expect_accounting_item.value_added_tax_id
  then
    failing := true;
    raise notice 'Different value_added_tax_id - expected "%", got "%"', t_expect_accounting_item.value_added_tax_id, accounting_item.value_added_tax_id;
  end if;

  if accounting_item.value_added_tax_percentage_id is distinct from t_expect_accounting_item.value_added_tax_percentage_id
  then
    failing := true;
    raise notice 'Different value_added_tax_percentage_id - expected "%", got "%"', t_expect_accounting_item.value_added_tax_percentage_id, accounting_item.value_added_tax_percentage_id;
  end if;

  if failing
  then
    raise exception 'Actual accounting item does not meet expectations';
  end if;
end
$$ language plpgsql immutable;

----

\echo\echo 'austria_tax_reclaimable_basic_debit'
savepoint austria_tax_reclaimable_basic_debit;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>true
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #2',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100,
    vat_groups=>array['{ "vatRate": 20, "netAmount": 83.33 }'::public.invoice_vat_group]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #2 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'NET',
    amount=>83.33,
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );
end $$;
rollback to savepoint austria_tax_reclaimable_basic_debit;

----

\echo\echo 'austria_tax_reclaimable_basic_credit'
savepoint austria_tax_reclaimable_basic_credit;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>true
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'CLIENT'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'CLIENT'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #2',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'OUTGOING_INVOICE',
    booking_type=>'CREDIT',
    invoice_total=>100,
    vat_groups=>array['{ "vatRate": 20, "netAmount": 83.33 }'::public.invoice_vat_group]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #2 (auto)',
    booking_type=>'CREDIT',
    amount_type=>'NET',
    amount=>83.33,
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );
end $$;
rollback to savepoint austria_tax_reclaimable_basic_credit;

----

\echo\echo 'austria_tax_reclaimable_multiple_basic'
savepoint austria_tax_reclaimable_multiple_basic;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>true
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(16)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(16)).value_added_tax_percentage_id
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #2',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100,
    vat_groups=>array[
      '{ "vatRate": 16, "netAmount": 44.83 }'::public.invoice_vat_group,
      '{ "vatRate": 20, "netAmount": 40 }'::public.invoice_vat_group
    ]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'NET',
    amount=>44.83,
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(16)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(16)).value_added_tax_percentage_id
  );

  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[2],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #2 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'NET',
    amount=>40,
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );
end $$;
rollback to savepoint austria_tax_reclaimable_multiple_basic;

----

\echo\echo 'austria_tax_reclaimable_prefer_more'
savepoint austria_tax_reclaimable_prefer_more;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>true
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  glas[2] := t_create_general_ledger_account(
    name=>'GLA #2',
    "number"=>'2'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.1',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.2',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100,
    vat_groups=>array['{ "vatRate": 20, "netAmount": 83.33 }'::public.invoice_vat_group]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.2 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'NET',
    amount=>83.33,
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );
end $$;
rollback to savepoint austria_tax_reclaimable_prefer_more;

----

\echo\echo 'austria_tax_reclaimable_no_vats_no_match'
savepoint austria_tax_reclaimable_no_vats_no_match;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>true
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  glas[2] := t_create_general_ledger_account(
    name=>'GLA #2',
    "number"=>'2'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.2'
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100,
    vat_groups=>array['{ "vatRate": 20, "netAmount": 83.33 }'::public.invoice_vat_group]
  );

  -- check
  if array_length(suggested_acc_items, 1) > 0 then
    raise exception 'Expected no accounting items suggestions, but got %', array_length(suggested_acc_items, 1);
  end if;
end $$;
rollback to savepoint austria_tax_reclaimable_no_vats_no_match;

----

\echo\echo 'austria_tax_reclaimable_glas_uses_provided_vats_as_weight'
savepoint austria_tax_reclaimable_glas_uses_provided_vats_as_weight;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>true
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  glas[2] := t_create_general_ledger_account(
    name=>'GLA #2',
    "number"=>'2'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.2'
  );

  -- glas[2] is used more, but glas[1] matches by VAT too

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100,
    vat_groups=>array['{ "vatRate": 20, "netAmount": 83.33 }'::public.invoice_vat_group]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'NET',
    amount=>83.33,
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );
end $$;
rollback to savepoint austria_tax_reclaimable_glas_uses_provided_vats_as_weight;

----

\echo\echo 'austria_tax_not_reclaimable_no_vats'
savepoint austria_tax_not_reclaimable_no_vats;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>false
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1'
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'TOTAL',
    amount=>100,
    value_added_tax_id=>null,
    value_added_tax_percentage_id=>null
  );
end $$;
rollback to savepoint austria_tax_not_reclaimable_no_vats;

----

\echo\echo 'austria_tax_not_reclaimable_no_vats_even_if_invoice_has_some'
savepoint austria_tax_not_reclaimable_no_vats_even_if_invoice_has_some;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>false
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1'
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100,
    vat_groups=>array[
      '{ "vatRate": 16, "netAmount": 0 }'::public.invoice_vat_group,
      '{ "vatRate": 20, "netAmount": 0 }'::public.invoice_vat_group
    ]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'TOTAL',
    amount=>100,
    value_added_tax_id=>null,
    value_added_tax_percentage_id=>null
  );
end $$;
rollback to savepoint austria_tax_not_reclaimable_no_vats_even_if_invoice_has_some;

----

\echo\echo 'austria_tax_reclaimable_glas_uses_provided_vats_as_weight'
savepoint austria_tax_reclaimable_glas_uses_provided_vats_as_weight;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>true
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  glas[2] := t_create_general_ledger_account(
    name=>'GLA #2',
    "number"=>'2'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.2'
  );

  -- glas[2] is used more, but glas[1] matches by VAT too

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100,
    vat_groups=>array['{ "vatRate": 20, "netAmount": 83.33 }'::public.invoice_vat_group]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'NET',
    amount=>83.33,
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );
end $$;
rollback to savepoint austria_tax_reclaimable_glas_uses_provided_vats_as_weight;

----

\echo\echo 'austria_tax_not_reclaimable_no_vats'
savepoint austria_tax_not_reclaimable_no_vats;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>false
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1'
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'TOTAL',
    amount=>100,
    value_added_tax_id=>null,
    value_added_tax_percentage_id=>null
  );
end $$;
rollback to savepoint austria_tax_not_reclaimable_no_vats;

----

\echo\echo 'austria_tax_not_reclaimable_no_vats_even_if_invoice_has_some'
savepoint austria_tax_not_reclaimable_no_vats_even_if_invoice_has_some;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>false
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1'
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100,
    vat_groups=>array[
      '{ "vatRate": 16, "netAmount": 0 }'::public.invoice_vat_group,
      '{ "vatRate": 20, "netAmount": 0 }'::public.invoice_vat_group
    ]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'TOTAL',
    amount=>100,
    value_added_tax_id=>null,
    value_added_tax_percentage_id=>null
  );
end $$;
rollback to savepoint austria_tax_not_reclaimable_no_vats_even_if_invoice_has_some;

----

\echo\echo 'austria_tax_not_reclaimable_no_vats_prefer_more'
savepoint austria_tax_not_reclaimable_no_vats_prefer_more;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>false
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  glas[2] := t_create_general_ledger_account(
    name=>'GLA #2',
    "number"=>'2'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.2'
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100,
    vat_groups=>array['{ "vatRate": 20, "netAmount": 83.33 }'::public.invoice_vat_group]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #2.2 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'TOTAL',
    amount=>100,
    value_added_tax_id=>null,
    value_added_tax_percentage_id=>null
  );
end $$;
rollback to savepoint austria_tax_not_reclaimable_no_vats_prefer_more;

----

\echo\echo 'austria_tax_not_reclaimable_no_vats_prefer_no_vats'
savepoint austria_tax_not_reclaimable_no_vats_prefer_no_vats;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>false
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  glas[2] := t_create_general_ledger_account(
    name=>'GLA #2',
    "number"=>'2'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #2'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #3.1',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #3.2',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[2],
    title=>'Acc. item #3.3'
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100,
    vat_groups=>array['{ "vatRate": 20, "netAmount": 83.33 }'::public.invoice_vat_group]
  );

  -- check
  -- TODO: this test is failing because of the unstable sort inside the GLA suggester
  -- perform t_expect_accounting_item(
  --   accounting_item=>suggested_acc_items[1],
  --   general_ledger_account_id=>glas[1],
  --   title=>'Acc. item #2 (auto)',
  --   booking_type=>'DEBIT',
  --   amount_type=>'TOTAL',
  --   amount=>100,
  --   value_added_tax_id=>null,
  --   value_added_tax_percentage_id=>null
  -- );
end $$;
rollback to savepoint austria_tax_not_reclaimable_no_vats_prefer_no_vats;

----

\echo\echo 'austria_tax_reclaimable_cent_difference_basic'
savepoint austria_tax_reclaimable_cent_difference_basic;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>true
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(19)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(19)).value_added_tax_percentage_id
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100.55,
    vat_groups=>array['{ "vatRate": 19, "netAmount": 84.5 }'::public.invoice_vat_group]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'TOTAL',
    amount=>100.55,
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(19)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(19)).value_added_tax_percentage_id
  );
end $$;
rollback to savepoint austria_tax_reclaimable_cent_difference_basic;

----

\echo\echo 'austria_tax_reclaimable_cent_difference_dont_suggest'
savepoint austria_tax_reclaimable_cent_difference_dont_suggest;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'AT',
    tax_reclaimable=>true
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1',
    -- net only items should not be suggested for cent difference offsetting
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(19, true)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(19, true)).value_added_tax_percentage_id
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>100.55,
    vat_groups=>array['{ "vatRate": 19, "netAmount": 84.5 }'::public.invoice_vat_group]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'NET',
    amount=>84.5,
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(19, true)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(19, true)).value_added_tax_percentage_id
  );
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[2],
    general_ledger_account_id=>null,
    title=>null,
    booking_type=>null,
    amount_type=>null,
    amount=>null,
    value_added_tax_id=>null,
    value_added_tax_percentage_id=>null
  );
end $$;
rollback to savepoint austria_tax_reclaimable_cent_difference_dont_suggest;

----

\echo\echo 'germany_tax_reclaimable_not_generated_for_all_percentages'
savepoint germany_tax_reclaimable_not_generated_for_all_percentages;
do $$
declare
  -- the index number matches the "N" in name "Partner/GLA #<N>"
  partners uuid[];
  glas uuid[];

  suggested_acc_items public.invoice_accounting_item[];
begin
  -- prepare
  perform t_set_client_company(
    country=>'DE',
    tax_reclaimable=>true
  );

  partners[1] := t_create_partner(
    name=>'Partner #1',
    vendor_number=>'70001',
    client_number=>'10001'
  );

  glas[1] := t_create_general_ledger_account(
    name=>'GLA #1',
    "number"=>'1'
  );

  perform t_create_accounting_item(
    partner_account_id=>t_account_from_partner(partners[1], 'VENDOR'),
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1',
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  -- suggest
  select array_agg(suggested_invoice_accounting_items)
  into suggested_acc_items
  from public.suggested_invoice_accounting_items(
    partner_company_id=>partners[1],
    document_type=>'INCOMING_INVOICE',
    booking_type=>'DEBIT',
    invoice_total=>97.74,
    vat_groups=>array[
      '{ "vatRate": 10, "netAmount": 48.87 }'::public.invoice_vat_group,
      '{ "vatRate": 20, "netAmount": 36.65 }'::public.invoice_vat_group
    ]
  );

  -- check
  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[1],
    general_ledger_account_id=>glas[1],
    title=>'Acc. item #1 (auto)',
    booking_type=>'DEBIT',
    amount_type=>'NET',
    amount=>36.65,
    value_added_tax_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_id,
    value_added_tax_percentage_id=>(t_get_value_added_tax_and_percentage(20)).value_added_tax_percentage_id
  );

  perform t_expect_accounting_item(
    accounting_item=>suggested_acc_items[2],
    general_ledger_account_id=>null,
    title=>null,
    booking_type=>null,
    amount_type=>null,
    amount=>null,
    value_added_tax_id=>null,
    value_added_tax_percentage_id=>null
  );
end $$;
rollback to savepoint germany_tax_reclaimable_not_generated_for_all_percentages;
