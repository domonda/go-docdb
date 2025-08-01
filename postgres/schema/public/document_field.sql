create type public.document_field_type as enum (
  'TEXT', -- text
  'NUMBER', -- float8
  'DATE', -- date
  'DATE_TIME', -- timestamptz
  'BOOLEAN', -- boolean
  'PARTNER_COMPANY', -- uuid references public.partner_company(id)
  'COMPANY_LOCATION', -- uuid references public.company_location(id)
  'INVOICE_PAYMENT_STATUS', -- public.invoice_payment_status
  'INVOICE', -- uuid references public.invoice(document_id)
  'IBAN', -- public.bank_iban
  'BIC', -- public.bank_bic
  'CURRENCY', -- public.currency_code
  'OTHER_DOCUMENT_TYPE', -- public.other_document_type
  'OTHER_DOCUMENT_CONTRACT_TYPE' -- public.other_document_contract_type
);

create table public.document_field (
  id uuid primary key default uuid_generate_v4(),

  "type" public.document_field_type not null,

  -- distinct name for internal referencing. ex: "invoice_date", "due_date", "total", "partner_company_id"
  name non_empty_text not null,
  constraint unique_name unique(name),

  created_at created_time not null
);

grant select on public.document_field to domonda_user;
grant select on public.document_field to domonda_wg_user;

create index document_field_name_idx on public.document_field (name);
create index document_field_name_gin_idx on public.document_field using gin (name gin_trgm_ops);

----

-- we dont use table inheritance because it does not play well with postgraphile

create table public.document_field_value_text (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value non_empty_text,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_text to domonda_user;
grant select on public.document_field_value_text to domonda_wg_user;
create index document_field_value_text_field_id_idx on public.document_field_value_text (field_id);
create index document_field_value_text_document_id_idx on public.document_field_value_text (document_id);
create index document_field_value_text_value_idx on public.document_field_value_text using gin (value gin_trgm_ops);
create index document_field_value_text_created_by_idx on public.document_field_value_text (created_by);

create table public.document_field_value_number (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value float8,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_number to domonda_user;
grant select on public.document_field_value_number to domonda_wg_user;
create index document_field_value_number_field_id_idx on public.document_field_value_number (field_id);
create index document_field_value_number_document_id_idx on public.document_field_value_number (document_id);
create index document_field_value_number_value_idx on public.document_field_value_number (value);
create index document_field_value_number_created_by_idx on public.document_field_value_number (created_by);

create table public.document_field_value_date (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value date,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_date to domonda_user;
grant select on public.document_field_value_date to domonda_wg_user;
create index document_field_value_date_field_id_idx on public.document_field_value_date (field_id);
create index document_field_value_date_document_id_idx on public.document_field_value_date (document_id);
create index document_field_value_date_value_idx on public.document_field_value_date (value);
create index document_field_value_date_created_by_idx on public.document_field_value_date (created_by);

create table public.document_field_value_date_time (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value timestamptz,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_date_time to domonda_user;
grant select on public.document_field_value_date_time to domonda_wg_user;
create index document_field_value_date_time_field_id_idx on public.document_field_value_date_time (field_id);
create index document_field_value_date_time_document_id_idx on public.document_field_value_date_time (document_id);
create index document_field_value_date_time_value_idx on public.document_field_value_date_time (value);
create index document_field_value_date_time_created_by_idx on public.document_field_value_date_time (created_by);

create table public.document_field_value_boolean (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value boolean,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_boolean to domonda_user;
grant select on public.document_field_value_boolean to domonda_wg_user;
create index document_field_value_boolean_field_id_idx on public.document_field_value_boolean (field_id);
create index document_field_value_boolean_document_id_idx on public.document_field_value_boolean (document_id);
create index document_field_value_boolean_value_idx on public.document_field_value_boolean (value);
create index document_field_value_boolean_created_by_idx on public.document_field_value_boolean (created_by);

create table public.document_field_value_partner_company (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value uuid references public.partner_company(id) on delete cascade, -- TODO: use some partner company as placeholder on delete to prevent document fields history loss

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, update, insert on public.document_field_value_partner_company to domonda_user;
grant select on public.document_field_value_partner_company to domonda_wg_user;
create index document_field_value_partner_company_field_id_idx on public.document_field_value_partner_company (field_id);
create index document_field_value_partner_company_document_id_idx on public.document_field_value_partner_company (document_id);
create index document_field_value_partner_company_value_idx on public.document_field_value_partner_company (value);
create index document_field_value_partner_company_created_by_idx on public.document_field_value_partner_company (created_by);

create table public.document_field_value_company_location (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value uuid references public.company_location(id) on delete cascade, -- TODO: use some company location as placeholder on delete to prevent document fields history loss

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_company_location to domonda_user;
grant select on public.document_field_value_company_location to domonda_wg_user;
create index document_field_value_company_location_field_id_idx on public.document_field_value_company_location (field_id);
create index document_field_value_company_location_document_id_idx on public.document_field_value_company_location (document_id);
create index document_field_value_company_location_value_idx on public.document_field_value_company_location (value);
create index document_field_value_company_location_created_by_idx on public.document_field_value_company_location (created_by);

create table public.document_field_value_invoice_payment_status (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value public.invoice_payment_status,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_invoice_payment_status to domonda_user;
grant select on public.document_field_value_invoice_payment_status to domonda_wg_user;
create index document_field_value_invoice_payment_status_field_id_idx on public.document_field_value_invoice_payment_status (field_id);
create index document_field_value_invoice_payment_status_document_id_idx on public.document_field_value_invoice_payment_status (document_id);
create index document_field_value_invoice_payment_status_value_idx on public.document_field_value_invoice_payment_status (value);
create index document_field_value_invoice_payment_status_created_by_idx on public.document_field_value_invoice_payment_status (created_by);

create table public.document_field_value_invoice (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value uuid references public.invoice(document_id) on delete cascade,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_invoice to domonda_user;
grant select on public.document_field_value_invoice to domonda_wg_user;
create index document_field_value_invoice_field_id_idx on public.document_field_value_invoice (field_id);
create index document_field_value_invoice_document_id_idx on public.document_field_value_invoice (document_id);
create index document_field_value_invoice_value_idx on public.document_field_value_invoice (value);
create index document_field_value_invoice_created_by_idx on public.document_field_value_invoice (created_by);

create table public.document_field_value_iban (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value public.bank_iban,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_iban to domonda_user;
grant select on public.document_field_value_iban to domonda_wg_user;
create index document_field_value_iban_field_id_idx on public.document_field_value_iban (field_id);
create index document_field_value_iban_document_id_idx on public.document_field_value_iban (document_id);
create index document_field_value_iban_value_idx on public.document_field_value_iban (value);
create index document_field_value_iban_created_by_idx on public.document_field_value_iban (created_by);

create table public.document_field_value_bic (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value public.bank_bic,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_bic to domonda_user;
grant select on public.document_field_value_bic to domonda_wg_user;
create index document_field_value_bic_field_id_idx on public.document_field_value_bic (field_id);
create index document_field_value_bic_document_id_idx on public.document_field_value_bic (document_id);
create index document_field_value_bic_value_idx on public.document_field_value_bic (value);
create index document_field_value_bic_created_by_idx on public.document_field_value_bic (created_by);

create table public.document_field_value_currency (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value public.currency_code,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_currency to domonda_user;
grant select on public.document_field_value_currency to domonda_wg_user;
create index document_field_value_currency_field_id_idx on public.document_field_value_currency (field_id);
create index document_field_value_currency_document_id_idx on public.document_field_value_currency (document_id);
create index document_field_value_currency_value_idx on public.document_field_value_currency (value);
create index document_field_value_currency_created_by_idx on public.document_field_value_currency (created_by);

create table public.document_field_value_other_document_type (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value public.other_document_type,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_other_document_type to domonda_user;
grant select on public.document_field_value_other_document_type to domonda_wg_user;
create index document_field_value_other_document_type_field_id_idx on public.document_field_value_other_document_type (field_id);
create index document_field_value_other_document_type_document_id_idx on public.document_field_value_other_document_type (document_id);
create index document_field_value_other_document_type_value_idx on public.document_field_value_other_document_type (value);
create index document_field_value_other_document_type_created_by_idx on public.document_field_value_other_document_type (created_by);

create table public.document_field_value_other_document_contract_type (
  id uuid primary key default uuid_generate_v4(),

  field_id    uuid not null references public.document_field(id) on delete restrict,
  document_id uuid not null references public.document(id) on delete cascade,

  value public.other_document_contract_type,

  created_by uuid not null
    default public.unknown_user_id()
    references public.user(id) on delete set default,
  created_at created_time not null
);
grant select, insert on public.document_field_value_other_document_contract_type to domonda_user;
grant select on public.document_field_value_other_document_contract_type to domonda_wg_user;
create index document_field_value_other_document_contract_type_field_id_idx on public.document_field_value_other_document_contract_type (field_id);
create index document_field_value_other_document_contract_type_document_id_idx on public.document_field_value_other_document_contract_type (document_id);
create index document_field_value_other_document_contract_type_value_idx on public.document_field_value_other_document_contract_type (value);
create index document_field_value_other_document_contract_type_created_by_idx on public.document_field_value_other_document_contract_type (created_by);

create function public.document_field_value_check()
returns trigger as $$
declare
  field public.document_field;
  field_value record = new; -- field values share the same table structure, only the "value" column is of different type
  table_to_field_type jsonb := $jsonb${
    "document_field_value_text": "TEXT",
    "document_field_value_number": "NUMBER",
    "document_field_value_date": "DATE",
    "document_field_value_date_time": "DATE_TIME",
    "document_field_value_boolean": "BOOLEAN",
    "document_field_value_partner_company": "PARTNER_COMPANY",
    "document_field_value_company_location": "COMPANY_LOCATION",
    "document_field_value_invoice_payment_status": "INVOICE_PAYMENT_STATUS",
    "document_field_value_invoice": "INVOICE",
    "document_field_value_iban": "IBAN",
    "document_field_value_bic": "BIC",
    "document_field_value_currency": "CURRENCY",
    "document_field_value_other_document_type": "OTHER_DOCUMENT_TYPE",
    "document_field_value_other_document_contract_type": "OTHER_DOCUMENT_CONTRACT_TYPE"
  }$jsonb$;
begin
  select * into field
  from public.document_field
  where id = field_value.field_id;

  if (table_to_field_type->>tg_table_name)::public.document_field_type <> field."type"
  then
    raise exception '% value cannot be used for field type %', table_to_field_type->>tg_table_name, field."type";
  end if;

  return null;
end
$$ language plpgsql stable;

create constraint trigger document_field_value_text_insert_or_update
  after insert or update on public.document_field_value_text
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_number_insert_or_update
  after insert or update on public.document_field_value_number
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_date_insert_or_update
  after insert or update on public.document_field_value_date
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_date_time_insert_or_update
  after insert or update on public.document_field_value_date_time
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_boolean_insert_or_update
  after insert or update on public.document_field_value_boolean
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_partner_company_insert_or_update
  after insert or update on public.document_field_value_partner_company
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_company_location_insert_or_update
  after insert or update on public.document_field_value_company_location
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_invoice_payment_status_insert_or_update
  after insert or update on public.document_field_value_invoice_payment_status
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_invoice_insert_or_update
  after insert or update on public.document_field_value_invoice
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_iban_insert_or_update
  after insert or update on public.document_field_value_iban
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_bic_insert_or_update
  after insert or update on public.document_field_value_bic
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_currency_insert_or_update
  after insert or update on public.document_field_value_currency
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_other_document_type_insert_or_update
  after insert or update on public.document_field_value_other_document_type
  for each row
  execute function public.document_field_value_check();
create constraint trigger document_field_value_other_document_contract_type_insert_or_update
  after insert or update on public.document_field_value_other_document_contract_type
  for each row
  execute function public.document_field_value_check();

----

create view public.document_field_value as (
  (
    select
      document_field_value_text.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      value as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_text.created_at
    from public.document_field_value_text
      inner join public.document_field on document_field.id = document_field_value_text.field_id
  ) union all (
    select
      document_field_value_number.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      value as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_number.created_at
    from public.document_field_value_number
      inner join public.document_field on document_field.id = document_field_value_number.field_id
  ) union all (
    select
      document_field_value_date.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      value as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_date.created_at
    from public.document_field_value_date
      inner join public.document_field on document_field.id = document_field_value_date.field_id
  ) union all (
    select
      document_field_value_date_time.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      value as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_date_time.created_at
    from public.document_field_value_date_time
      inner join public.document_field on document_field.id = document_field_value_date_time.field_id
  ) union all (
    select
      document_field_value_boolean.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      value as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_boolean.created_at
    from public.document_field_value_boolean
      inner join public.document_field on document_field.id = document_field_value_boolean.field_id
  ) union all (
    select
      document_field_value_partner_company.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      value as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_partner_company.created_at
    from public.document_field_value_partner_company
      inner join public.document_field on document_field.id = document_field_value_partner_company.field_id
  ) union all (
    select
      document_field_value_company_location.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      value as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_company_location.created_at
    from public.document_field_value_company_location
      inner join public.document_field on document_field.id = document_field_value_company_location.field_id
  ) union all (
    select
      document_field_value_invoice_payment_status.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      value as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_invoice_payment_status.created_at
    from public.document_field_value_invoice_payment_status
      inner join public.document_field on document_field.id = document_field_value_invoice_payment_status.field_id
  ) union all (
    select
      document_field_value_invoice.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      value as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_invoice.created_at
    from public.document_field_value_invoice
      inner join public.document_field on document_field.id = document_field_value_invoice.field_id
  ) union all (
    select
      document_field_value_iban.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      value as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_iban.created_at
    from public.document_field_value_iban
      inner join public.document_field on document_field.id = document_field_value_iban.field_id
  ) union all (
    select
      document_field_value_bic.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      value as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_bic.created_at
    from public.document_field_value_bic
      inner join public.document_field on document_field.id = document_field_value_bic.field_id
  ) union all (
    select
      document_field_value_currency.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      value as value_currency,
      null::public.other_document_type as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_currency.created_at
    from public.document_field_value_currency
      inner join public.document_field on document_field.id = document_field_value_currency.field_id
  ) union all (
    select
      document_field_value_other_document_type.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      value as value_other_document_type,
      null::public.other_document_contract_type as value_other_document_contract_type,

      created_by,
      document_field_value_other_document_type.created_at
    from public.document_field_value_other_document_type
      inner join public.document_field on document_field.id = document_field_value_other_document_type.field_id
  ) union all (
    select
      document_field_value_other_document_contract_type.id,

      field_id,
      document_field.type as field_type,
      document_field.name as field_name,

      document_id,

      null::text as value_text,
      null::float8 as value_number,
      null::date as value_date,
      null::timestamptz as value_date_time,
      null::boolean as value_boolean,
      null::uuid as value_partner_company,
      null::uuid as value_company_location,
      null::public.invoice_payment_status as value_invoice_payment_status,
      null::uuid as value_invoice,
      null::public.bank_iban as value_iban,
      null::public.bank_bic as value_bic,
      null::public.currency_code as value_currency,
      null::public.other_document_type as value_other_document_type,
      value as value_other_document_contract_type,

      created_by,
      document_field_value_other_document_contract_type.created_at
    from public.document_field_value_other_document_contract_type
      inner join public.document_field on document_field.id = document_field_value_other_document_contract_type.field_id
  )
);

grant select on public.document_field_value to domonda_user;
grant select on public.document_field_value to domonda_wg_user;

comment on column public.document_field_value.id is '@notNull';
comment on column public.document_field_value.field_id is '@notNull';
comment on column public.document_field_value.field_type is '@notNull';
comment on column public.document_field_value.field_name is '@notNull';
comment on column public.document_field_value.document_id is '@notNull';
comment on column public.document_field_value.created_by is '@notNull';
comment on column public.document_field_value.created_at is '@notNull';
comment on view public.document_field_value is $$
@primaryKey id

@foreignKey (field_id) references public.document_field (id)

@foreignKey (document_id) references public.document (id)

@foreignKey (value_partner_company) references public.partner_company (id)
@foreignKey (value_company_location) references public.company_location (id)
@foreignKey (value_invoice) references public.invoice (document_id)

@foreignKey (created_by) references public.user (id)
$$;
