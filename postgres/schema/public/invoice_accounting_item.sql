-- D/C booking type calculations are switched because of double-entry bookkeeping:
-- A debit in one account offsets a credit in another, the sum of all debits must equal the sum of all credits.

create type public.invoice_accounting_item_booking_type as enum (
    'DEBIT', -- money coming in (+)
    'CREDIT' -- money going out (-)
);

create type public.invoice_accounting_item_amount_type as enum (
    'TOTAL',
    'NET'
);

create table public.invoice_accounting_item (
    id uuid primary key default uuid_generate_v4(),

    invoice_document_id uuid not null references public.invoice(document_id) on delete cascade,

    general_ledger_account_id uuid not null references public.general_ledger_account(id) on delete restrict,

    title text not null check(length(trim(title)) > 0),

    booking_type public.invoice_accounting_item_booking_type not null,
    amount_type  public.invoice_accounting_item_amount_type not null,

    amount float8 not null check(amount >= 0), -- must be positive

    value_added_tax_id            uuid references public.value_added_tax(id) on delete restrict,
    value_added_tax_percentage_id uuid references public.value_added_tax_percentage(id) on delete restrict,

    -- when the percentage is set, the vat must be as well
    constraint percentage_and_vat_check check((value_added_tax_percentage_id is null) or (value_added_tax_id is not null)),

    updated_by uuid references public.user(id) on delete set null,
    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system-user ID for unknown user
        references public.user(id) on delete set default,

    updated_at updated_time not null,
    created_at created_time not null
);

create index invoice_accounting_item_invoice_document_id_idx on public.invoice_accounting_item (invoice_document_id);
create index invoice_accounting_item_general_ledger_account_id_idx on public.invoice_accounting_item (general_ledger_account_id);
create index invoice_accounting_item_value_added_tax_id_idx on public.invoice_accounting_item (value_added_tax_id);
create index invoice_accounting_item_value_added_tax_percentage_id_idx on public.invoice_accounting_item (value_added_tax_percentage_id);

grant all on public.invoice_accounting_item to domonda_user;
grant select on public.invoice_accounting_item to domonda_wg_user;

----

create function public.invoice_accounting_item_vat_is_sane(
    invoice_accounting_item public.invoice_accounting_item
) returns boolean as
$$
    select
        case
            -- when `value_added_tax_percentage_id` is set, check if it belongs to the `vat`
            when (invoice_accounting_item.value_added_tax_percentage_id is not null) then (
                select exists (
                    select 1 from public.value_added_tax_percentage
                    where (
                        invoice_accounting_item.value_added_tax_id = value_added_tax_percentage.value_added_tax_id
                    ) and (
                        invoice_accounting_item.value_added_tax_percentage_id = value_added_tax_percentage.id
                    )
                )
            )
            --- when `value_added_tax_id` is set and it dictates that the amount must be NET
            when (invoice_accounting_item.value_added_tax_id is not null) then (
                select exists (
                    select 1 from public.value_added_tax
                    where (
                        invoice_accounting_item.value_added_tax_id = value_added_tax.id
                    ) and (
                        (not value_added_tax.net_only_amount) or (
                            invoice_accounting_item.amount_type <> 'NET'
                        )
                    )
                )
            )
            --- when `value_added_tax_id` is set, but not the `vat_percentage`; check if it should exist
            when (invoice_accounting_item.value_added_tax_id is not null) and (invoice_accounting_item.value_added_tax_percentage_id is null) then (
                select not exists (
                    select 1 from public.value_added_tax_percentage
                    where (
                        invoice_accounting_item.value_added_tax_id = value_added_tax_percentage.value_added_tax_id
                    )
                )
            )
            else true
        end
$$
language sql stable;

comment on function public.invoice_accounting_item_vat_is_sane is E'@notNull\nSanity check which evaluates 3 cases. When the `VATPercentage` is set, does it belong to the `VAT`? When the `VAT` is set, does the `amountType` comply with what the `VAT` dictates? When the `VAT` is set, but `VATPercentage` is not; should it be?';

----

create function public.invoice_accounting_item_sign(
  invoice_accounting_item public.invoice_accounting_item
) returns int as $$
  select case
    when invoice_accounting_item.booking_type = 'DEBIT' then -1
    else 1
  end
$$ language sql immutable strict;
comment on function public.invoice_accounting_item_sign is E'@notNull\nThe expected accounting sign of the accounting item.';

create function public.invoice_accounting_item_total(
  invoice_accounting_item public.invoice_accounting_item
) returns float8 as $$
  select case
    when invoice_accounting_item.amount_type = 'TOTAL'
      or invoice_accounting_item.value_added_tax_percentage_id is null
      or (select net_only_amount from public.value_added_tax where id = invoice_accounting_item.value_added_tax_id)
    then round(invoice_accounting_item.amount::numeric, 2)::float8
    else (
      select round((invoice_accounting_item.amount * (100 + percentage) / 100)::numeric, 2)::float8
      from public.value_added_tax_percentage
      where value_added_tax_percentage.id = invoice_accounting_item.value_added_tax_percentage_id
    )
  end
$$ language sql stable;
comment on function public.invoice_accounting_item_total is E'@notNull\nIs the net amount plus the value added tax. Always positive.';

create function public.invoice_accounting_item_signed_total(
  invoice_accounting_item public.invoice_accounting_item
) returns float8 as $$
  select public.invoice_accounting_item_total(invoice_accounting_item) * public.invoice_accounting_item_sign(invoice_accounting_item)
$$ language sql stable;
comment on function public.invoice_accounting_item_signed_total is E'@notNull\nIs the net amount plus the value added tax. Amount is signed looking at the item''s booking type.';

create function private.invoice_accounting_items_total_sum(
  invoice_accounting_items public.invoice_accounting_item[]
) returns float8 as $$
  select sum(public.invoice_accounting_item_total(invoice_accounting_item))
  from unnest(invoice_accounting_items) as invoice_accounting_item
$$ language sql stable strict;

create function private.signed_invoice_accounting_items_total_sum(
  invoice_accounting_items public.invoice_accounting_item[]
) returns float8 as $$
  select sum(public.invoice_accounting_item_signed_total(invoice_accounting_item))
  from unnest(invoice_accounting_items) as invoice_accounting_item
$$ language sql stable strict;

create function public.invoice_accounting_item_net(
  invoice_accounting_item public.invoice_accounting_item
) returns float8 as $$
  select case
    when invoice_accounting_item.amount_type = 'NET'
      or invoice_accounting_item.value_added_tax_percentage_id is null
    then round(invoice_accounting_item.amount::numeric, 2)::float8
    else (
      select round((invoice_accounting_item.amount * 100 / (100 + percentage))::numeric, 2)::float8
      from public.value_added_tax_percentage
      where value_added_tax_percentage.id = invoice_accounting_item.value_added_tax_percentage_id
    )
  end
$$ language sql stable;
comment on function public.invoice_accounting_item_net is E'@notNull\nIs the total amount minus the value added tax. Always positive.';

create function public.invoice_accounting_item_signed_net(
  invoice_accounting_item public.invoice_accounting_item
) returns float8 as $$
  select public.invoice_accounting_item_net(invoice_accounting_item) * public.invoice_accounting_item_sign(invoice_accounting_item)
$$ language sql stable;
comment on function public.invoice_accounting_item_signed_net is E'@notNull\nIs the total amount minus the value added tax. Amount is signed looking at the item''s booking type.';

create function private.invoice_accounting_items_net_sum(
  invoice_accounting_items public.invoice_accounting_item[]
) returns float8 as $$
  select sum(public.invoice_accounting_item_net(invoice_accounting_item))
  from unnest(invoice_accounting_items) as invoice_accounting_item
$$ language sql stable strict;

create function private.signed_invoice_accounting_items_net_sum(
  invoice_accounting_items public.invoice_accounting_item[]
) returns float8 as $$
  select sum(public.invoice_accounting_item_signed_net(invoice_accounting_item))
  from unnest(invoice_accounting_items) as invoice_accounting_item
$$ language sql stable strict;

create function public.invoice_accounting_item_tax(
  invoice_accounting_item public.invoice_accounting_item
) returns float8 as $$
  select round((
    public.invoice_accounting_item_total(invoice_accounting_item) - public.invoice_accounting_item_net(invoice_accounting_item)
  )::numeric, 2)::float8
$$ language sql stable;
comment on function public.invoice_accounting_item_tax is E'@notNull\nTax amount is total minus net. Always positive.';
----

-- calculates the difference left to the `Invoice.total` summing up `InvoiceAccountingItem.amount`
-- the result is sign-sensitive. meaning negative amount is `CREDIT` and positive `DEBIT`.
create function private.calc_remaining_invoice_accounting_item_amount(
  invoice_document_id              uuid,
  skip_invoice_accounting_item_ids uuid[] = '{}'
) returns float8 as $$
declare
  signed_invoice_amount float8;
  signed_invoice_accounting_items_amount_sum float8;
  diff float8;
begin
  -- signed invoice total is the amount
  select public.invoice_signed_total(invoice)
    into signed_invoice_amount
  from public.invoice
  where invoice.document_id = calc_remaining_invoice_accounting_item_amount.invoice_document_id;

  -- nothing to calculate when there is no amount
  if signed_invoice_amount is null then
    return null;
  end if;

  -- sum signed invoice accounting items belonging to the invoice
  select private.signed_invoice_accounting_items_total_sum(array_agg(invoice_accounting_item))
    into signed_invoice_accounting_items_amount_sum
  from public.invoice_accounting_item
  where invoice_accounting_item.invoice_document_id = calc_remaining_invoice_accounting_item_amount.invoice_document_id;

  if signed_invoice_accounting_items_amount_sum is null then
    -- there's no acc. items, set the sum to 0 so that the diff calculation is correct
    signed_invoice_accounting_items_amount_sum := 0;

    if signed_invoice_amount = 0
    then
      -- when invoice amount is 0, return null so that the user must create one acc. item
      return null;
    end if;

  end if;

  -- calculate difference with mathematically correct rounding
  diff := round(signed_invoice_amount::numeric, 2) - round(signed_invoice_accounting_items_amount_sum::numeric, 2);

  return diff;
end
$$ language plpgsql stable
cost 100000;
comment on function private.calc_remaining_invoice_accounting_item_amount is 'Derives the difference left to the `Invoice.total` summing up `InvoiceAccountingItem.amount`. The result is sign-sensitive.';

----

create function public.delete_invoice_accounting_item(
    id uuid
) returns public.invoice_accounting_item as
$$
    delete from public.invoice_accounting_item
    where id = delete_invoice_accounting_item.id
    returning *
$$
language sql volatile;

----

create function public.invoice_accounting_items_remaining_amount(
    invoice public.invoice
) returns float8 as
$$
    select private.calc_remaining_invoice_accounting_item_amount(invoice_document_id => invoice.document_id)
$$
language sql stable;

comment on function public.invoice_accounting_items_remaining_amount is 'Calculates the difference between the summed amounts of the `InvoiceAccountingItem`s and this `Invoice` amount (total).';

----

create function public.invoice_accounting_items_remaining_amount_is_zero(
    invoice public.invoice
) returns boolean as
$$
    select public.invoice_accounting_items_remaining_amount(invoice) is not distinct from 0
$$
language sql stable;

comment on function public.invoice_accounting_items_remaining_amount_is_zero is E'@notNull\nChecks if the difference between the summed amounts of the `InvoiceAccountingItem`s and this `Invoice` amount (total) is *zero*.';

----

create function public.invoice_accounting_item_value_added_tax_code_for_accounting(
    invoice_accounting_item public.invoice_accounting_item,
    accounting_system       public.accounting_system
) returns public.value_added_tax_code as
$$
    select vcfa.*
    from
        public.document as d
            inner join public.client_company as cc on cc.company_id = d.client_company_id,
        public.value_added_tax_code_for_accounting(
            invoice_accounting_item_value_added_tax_code_for_accounting.accounting_system,
            cc.tax_reclaimable,
            invoice_accounting_item.value_added_tax_id,
            invoice_accounting_item.value_added_tax_percentage_id,
            cc.company_id
        ) as vcfa
    where d.id = invoice_accounting_item.invoice_document_id
$$
language sql stable strict;


----

create function public.invoice_accounting_item_value_added_tax_code(
    invoice_accounting_item public.invoice_accounting_item
) returns public.value_added_tax_code as
$$
    select vcfa.*
    from
        public.document as d
            inner join public.client_company as cc on cc.company_id = d.client_company_id,
        public.value_added_tax_code_for_accounting(
            public.vat_accounting_system(cc.accounting_system),
            cc.tax_reclaimable,
            invoice_accounting_item.value_added_tax_id,
            invoice_accounting_item.value_added_tax_percentage_id,
            cc.company_id
        ) as vcfa
    where d.id = invoice_accounting_item.invoice_document_id
$$
language sql stable strict;

----

create function public.invoice_accounting_item_general_ledger_account_number(
    item public.invoice_accounting_item
) returns account_no as
$$
    select "number"
    from public.general_ledger_account
    where id = item.general_ledger_account_id
$$
language sql stable strict;

comment on function public.invoice_accounting_item_general_ledger_account_number is E'@notNull\nGeneral ledger account number of the accounting item';

----

create function public.invoice_accounting_item_partner_account_number(
    item public.invoice_accounting_item
) returns account_no as
$$
    select (public.invoice_partner_account(invoice)).number
    from public.invoice
    where invoice.document_id = item.invoice_document_id
$$
language sql stable strict;

comment on function public.invoice_accounting_item_partner_account_number is E'@notNull\nPartner account number of the accounting item, or null if the invoice has no partner';

----

create function public.invoice_accounting_item_debit_account_number(
    item public.invoice_accounting_item
) returns account_no as
$$
  select
    case when (document_category.document_type = 'INCOMING_INVOICE')
      then public.invoice_accounting_item_general_ledger_account_number(item)
      else public.invoice_accounting_item_partner_account_number(item)
    end
  from public.document
    inner join public.document_category
      on document_category.id = document.category_id
  where document.id = item.invoice_document_id
$$
language sql stable strict;

comment on function public.invoice_accounting_item_debit_account_number is E'@notNull\nDebit account number for the accounting item, either general ledger or partner account depending on incoming or outgoing invoice';

----

create function public.invoice_accounting_item_credit_account_number(
    item public.invoice_accounting_item
) returns account_no as
$$
  select
    case when (document_category.document_type = 'OUTGOING_INVOICE')
      then public.invoice_accounting_item_general_ledger_account_number(item)
      else public.invoice_accounting_item_partner_account_number(item)
    end
  from public.document
    inner join public.document_category
      on document_category.id = document.category_id
  where document.id = item.invoice_document_id
$$
language sql stable strict;

comment on function public.invoice_accounting_item_credit_account_number is E'@notNull\nCredit account number for the accounting item, either general ledger or partner account depending on incoming or outgoing invoice';

----

create function public.invoice_booking_type(
    inv public.invoice
) returns public.invoice_accounting_item_booking_type as
$$
  select
    case when (document_category.document_type = 'INCOMING_INVOICE')
      then
        case when inv.credit_memo
          then 'CREDIT'::public.invoice_accounting_item_booking_type -- money coming in
          else 'DEBIT'::public.invoice_accounting_item_booking_type  -- money going out
        end
      else
        case when inv.credit_memo
          then 'DEBIT'::public.invoice_accounting_item_booking_type  -- money going out
          else 'CREDIT'::public.invoice_accounting_item_booking_type -- money coming in
        end
    end
  from public.document
    inner join public.document_category
      on document_category.id = document.category_id
  where document.id = inv.document_id
$$
language sql stable strict;

comment on function public.invoice_booking_type is E'@notNull\nGeneral booking type (DEBIT or CREDIT) of the invoice depending on if it''s an incoming or outgoing invoice and if it''s a credit-memo.';
