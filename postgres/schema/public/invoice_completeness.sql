-- tend to map the details the same way the column
-- names are but in constant case. this way I can jus
-- lowercase them to access a specific key's value
create type public.invoice_completeness_detail as enum (
  'INVOICE_NUMBER',
  'INVOICE_DATE',
  'PARTNER_COMPANY_ID',
  'PARTNER_ACCOUNT',
  'TOTAL',
  'IBAN',
  'NET',
  'DUE_DATE',
  'DISCOUNT_UNTIL',
  'BIC',
  'ACCOUNTING_ITEMS',
  'ACCOUNTING_ITEMS_NO_REMAINING_AMOUNT',
  'ACCOUNTING_ITEMS_COST_CENTERS',
  'ACCOUNTING_ITEMS_COST_UNITS',
  'REAL_ESTATE_OBJECT' -- TODO: doesn't really belong here because the REO is a document property, not an invoice one
);

create type public.invoice_completeness_level as enum (
  'INVOICE',
  'ACCOUNTING_ITEMS',
  'REAL_ESTATE_OBJECT' -- TODO: doesn't really belong here because the REO is a document property, not an invoice one
);

----

create function public.invoice_completeness_details_for_level(
  "level" public.invoice_completeness_level
) returns public.invoice_completeness_detail[] as
$$
  select (case "level"
    when 'INVOICE' then array[
      'INVOICE_NUMBER',
      'INVOICE_DATE',
      'PARTNER_COMPANY_ID',
      'TOTAL',
      'NET'
    ]
    when 'ACCOUNTING_ITEMS' then array[
      'ACCOUNTING_ITEMS_NO_REMAINING_AMOUNT'
    ]
    when 'REAL_ESTATE_OBJECT' then array[
      'REAL_ESTATE_OBJECT'
    ]
    else '{}'
  end)::public.invoice_completeness_detail[]
$$
language sql strict immutable;
comment on function public.invoice_completeness_details_for_level is '@notNull';

----

create type public.invoice_completeness_details_for_level as (
  "level" public.invoice_completeness_level,
  details public.invoice_completeness_detail[]
);
comment on column public.invoice_completeness_details_for_level.level is '@notNull';
comment on column public.invoice_completeness_details_for_level.details is '@notNull';

create function public.all_invoice_completeness_details_for_levels()
returns public.invoice_completeness_details_for_level[] as
$$
  select
    array_agg((
      "level",
      public.invoice_completeness_details_for_level("level")
    )::public.invoice_completeness_details_for_level)
  from unnest(enum_range(null::public.invoice_completeness_level)) as "level"
$$
language sql strict immutable; -- can be immutable because the enum values seldomly change
comment on function public.all_invoice_completeness_details_for_levels is '@notNull';

----

create function public.invoice_has_completeness_details(
  invoice public.invoice,
  details public.invoice_completeness_detail[]
) returns boolean as $$
declare
  stmt   text;
  detail public.invoice_completeness_detail;
  has    boolean;
begin
  if array_length(details, 1) = 0 then
    raise exception 'At least one completeness details has to be provided';
  end if;
  if array_position(details, null) is not null then
    raise exception 'One of completeness details is null';
  end if;

  stmt := 'select ';
  foreach detail in array invoice_has_completeness_details.details
  loop
    case detail
      when 'REAL_ESTATE_OBJECT' then
        stmt := stmt || 'exists (select from public.document_real_estate_object where document_real_estate_object.document_id = $1.document_id) and ';
      when 'ACCOUNTING_ITEMS' then
        stmt := stmt || 'exists (select from public.invoice_accounting_item where invoice_accounting_item.invoice_document_id = $1.document_id) and ';
      when 'ACCOUNTING_ITEMS_NO_REMAINING_AMOUNT' then
        stmt := stmt || 'public.invoice_accounting_items_remaining_amount_is_zero($1) and ';
      when 'ACCOUNTING_ITEMS_COST_CENTERS' then
        stmt := stmt || $stmt$(select every(not (invoice_accounting_item_cost_center is null)) from public.invoice_accounting_item
          left join public.invoice_accounting_item_cost_center on invoice_accounting_item_cost_center.invoice_accounting_item_id = invoice_accounting_item.id
        where invoice_accounting_item.invoice_document_id = i.document_id) and $stmt$;
      when 'ACCOUNTING_ITEMS_COST_UNITS' then
        stmt := stmt || $stmt$(select every(not (invoice_accounting_item_cost_unit is null)) from public.invoice_accounting_item
          left join public.invoice_accounting_item_cost_unit on invoice_accounting_item_cost_unit.invoice_accounting_item_id = invoice_accounting_item.id
        where invoice_accounting_item.invoice_document_id = i.document_id) and $stmt$;
      when 'PARTNER_ACCOUNT' then
        stmt := stmt || $stmt$
            public.invoice_account_number(i) is not null and
        $stmt$;
      when 'IBAN' then
        stmt := stmt || $stmt$
          public.invoice_payment_iban(i) is not null and
        $stmt$;
      when 'BIC' then
        stmt := stmt || $stmt$
          public.invoice_payment_bic(i) is not null and
        $stmt$;
      when 'DUE_DATE' then
        stmt := stmt || $stmt$
          public.invoice_payment_due_date(i) is not null and
        $stmt$;
      when 'DISCOUNT_UNTIL' then
        stmt := stmt || $stmt$
          public.invoice_payment_discount_due_date(i) is not null and
        $stmt$;
      else
        stmt := stmt || format(
          '$1.%1$I is not null and ',
          lower(detail::text) -- %1$I
        );
    end case;
  end loop;
  stmt := trim(trailing 'and ' from stmt);

  execute stmt
  into has
  using invoice_has_completeness_details.invoice;

  return has;
end
$$ language plpgsql immutable strict;
comment on function public.invoice_has_completeness_details is '@notNull';

create function public.invoice_has_completeness_level(
  invoice public.invoice,
  "level" public.invoice_completeness_level
) returns boolean as $$
  select public.invoice_has_completeness_details(
    invoice_has_completeness_level.invoice,
    public.invoice_completeness_details_for_level(invoice_has_completeness_level.level)
  )
$$ language sql immutable strict;
comment on function public.invoice_has_completeness_level is '@notNull';
