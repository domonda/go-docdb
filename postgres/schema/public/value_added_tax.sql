create type public.value_added_tax_type as enum (
  'PAYABLE',
  'RECLAIMABLE'
);

create table public.value_added_tax (
  id uuid primary key default uuid_generate_v4(),

  introduced_at date,
  expired_at    date,

  "type"     public.value_added_tax_type not null,
  name       text not null,
  short_name text,

  net_only_amount boolean not null default false,
  vat_id_required boolean not null,
  country         country_code not null,

  -- helps with accounting items suggestions where the VAT was not detected using
  -- statistics, so we use the "default" one for a given percentage
  --
  -- see invoice_accounting_item_suggestions.sql#public.suggested_invoice_accounting_items for more details
  "default" boolean not null default false,
  index     int not null default 0,

  -- names are unique per country
  unique(name, country),
  unique(short_name, country),

  updated_at updated_time not null,
  created_at created_time not null
);

comment on column public.value_added_tax.expired_at is 'The date on which this `VAT` expired. If the date is set and is in the past, this `VAT` should be hidden.';
comment on column public.value_added_tax.net_only_amount is 'If the belonging `InvoiceAccountingItem` must have the amount type `NET`.';
comment on column public.value_added_tax.vat_id_required is 'If the belonging `Invoice` must have a VATID assigned.';
comment on column public.value_added_tax.country is 'In which country is this `VAT` applicable. The `VAT` is filtered down by the country of the `ClientCompany`.';

create unique index value_added_tax_only_one_default_per_country_and_type on public.value_added_tax ("type", country) where ("default");

create index value_added_tax_type_idx on public.value_added_tax ("type");
create index value_added_tax_default_idx on public.value_added_tax ("default");
create index value_added_tax_net_only_amount_idx on public.value_added_tax (net_only_amount);
create index value_added_tax_country_idx on public.value_added_tax (country);

grant select on public.value_added_tax to domonda_user;
grant select on public.value_added_tax to domonda_wg_user;

----

create function public.value_added_tax_full_name(
  vat public.value_added_tax
) returns text as
$$
  select
    case
      when vat.short_name is null then vat.name
      else vat.short_name || ' (' || vat.name || ')'
    end
$$
language sql immutable;

comment on function public.value_added_tax_full_name is '@notNull';

----

create function public.value_added_tax_short_name_or_name(
  vat public.value_added_tax
) returns text as
$$
  select coalesce(vat.short_name, vat.name)
$$
language sql immutable;

comment on function public.value_added_tax_short_name_or_name is '@notNull';

----

create table public.value_added_tax_percentage (
  id                 uuid primary key default uuid_generate_v4(),
  value_added_tax_id uuid not null references public.value_added_tax(id) on delete cascade,

  -- introduced_at date, -- TODO add column
  expired_at date,

  percentage float8 not null check(percentage >= 0 and percentage < 100),
  unique(value_added_tax_id, percentage),

  created_at created_time not null
);

comment on column public.value_added_tax_percentage.expired_at is 'The date on which this `VATPercentage` expired. If the date is set and is in the past, this `VATPercentage` should be hidden.';
comment on column public.value_added_tax_percentage.percentage is 'The `VATPercentage` ranging from 0 to 100 with decimal places support.';

create index value_added_tax_percentage_value_added_tax_id_idx on public.value_added_tax_percentage (value_added_tax_id);

grant select on public.value_added_tax_percentage to domonda_user;
grant select on public.value_added_tax_percentage to domonda_wg_user;


----

create function public.value_added_tax_amount_type_must_be_net(
  vat public.value_added_tax
) returns boolean as
$$
  select (
    -- vat dictates so
    vat.net_only_amount
  ) or (
    -- no vat percentages
    not exists (
        select 1 from public.value_added_tax_percentage
        where (vat.id = value_added_tax_percentage.value_added_tax_id)
    )
  )
$$
language sql immutable;

comment on function public.value_added_tax_amount_type_must_be_net is '@notNull';

----

create table public.value_added_tax_code (
  id uuid primary key default uuid_generate_v4(),

  -- tax codes can be added on tax or percentage level
  value_added_tax_id            uuid references public.value_added_tax(id) on delete cascade,
  value_added_tax_percentage_id uuid references public.value_added_tax_percentage(id) on delete cascade,
  constraint tax_or_percentage_check check((value_added_tax_id is null) <> (value_added_tax_percentage_id is null)),

  accounting_system public.accounting_system not null,
  reclaimable       boolean not null,

  -- used when the client uses custom VAT codes instead of the recommended ones
  -- is here only for EDGE-CASES, all domonda clients should use the recommended codes!
  client_company_id uuid references public.client_company(company_id) on delete cascade,

  code text not null check(length(code) > 0),

  created_at created_time not null
);

create index value_added_tax_code_value_added_tax_id_idx on public.value_added_tax_code (value_added_tax_id);
create index value_added_tax_code_value_added_tax_percentage_id_idx on public.value_added_tax_code (value_added_tax_percentage_id);
create index value_added_tax_code_client_company_id_idx on public.value_added_tax_code (client_company_id);

-- Can't check for unique code, because the same code can be used for different countries
-- but the country is stored in public.value_added_tax and can't be merged in an index.
-- Failes with real data in our DB because of duplicates:
-- create unique index value_added_tax_code_code_unique
--   on public.value_added_tax_code (accounting_system, code)
--   where (client_company_id is null);

-- But codes are certainly unique per client company
create unique index value_added_tax_code_cc_code_unique
  on public.value_added_tax_code (accounting_system, code, client_company_id)
  where (client_company_id is not null);

-- unique w client company
create unique index value_added_tax_code_unique
  on public.value_added_tax_code (accounting_system, value_added_tax_id, reclaimable, client_company_id)
  where (value_added_tax_id is not null);
create unique index value_added_tax_percentage_code_unique
  on public.value_added_tax_code (accounting_system, value_added_tax_percentage_id, reclaimable, client_company_id)
  where (value_added_tax_percentage_id is not null);

-- unique w/o client company
create unique index value_added_tax_code_unique_client_company_id_null
  on public.value_added_tax_code (accounting_system, value_added_tax_id, reclaimable)
  where ((client_company_id is null) and (value_added_tax_id is not null));
create unique index value_added_tax_percentage_code_unique_client_company_id_null
  on public.value_added_tax_code (accounting_system, value_added_tax_percentage_id, reclaimable)
  where ((client_company_id is null) and (value_added_tax_percentage_id is not null));

comment on column public.value_added_tax_code.client_company_id is 'If a `ClientCompany` uses custom codes for `VAT`s, this field will be populated and it supersedes any other definition for a given accounting system.';
comment on column public.value_added_tax_code.reclaimable is 'The `VATCode` for when the `ClientCompany` cannot re-claim the taxes.';

grant select on public.value_added_tax_code to domonda_user;

----

create function public.value_added_tax_code_for_accounting(
  accounting_system             public.accounting_system,
  reclaimable                   boolean,
  value_added_tax_id            uuid = null,
  value_added_tax_percentage_id uuid = null,
  client_company_id             uuid = null
) returns public.value_added_tax_code as
$$
  select c.*
  from public.value_added_tax_code as c
  where c.accounting_system = value_added_tax_code_for_accounting.accounting_system
	  and c.reclaimable = value_added_tax_code_for_accounting.reclaimable
    -- if no percentage specific code exists, the general vat one will be used (check the order)
	  and (c.value_added_tax_percentage_id = value_added_tax_code_for_accounting.value_added_tax_percentage_id
      or c.value_added_tax_id = value_added_tax_code_for_accounting.value_added_tax_id
    )
    -- if no client specific code is set, the recommended one will be used (check the order)
    and (c.client_company_id = value_added_tax_code_for_accounting.client_company_id
      or c.client_company_id is null
    )
	order by
      c.value_added_tax_percentage_id nulls last, -- prefer percentage specific codes
      c.client_company_id             nulls last  -- prefer the client specific codes
	limit 1
$$
language sql stable;


