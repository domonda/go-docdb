create type public.document_category_internal_number_mode as enum (
    'MANUAL',
    'COUNT_UP',
    'EXTERNAL_COUNT_UP'
);

create table public.document_category (
    id uuid primary key,

    client_company_id uuid not null references public.client_company(company_id) on delete cascade,
    document_type     public.document_type not null,
    booking_type      public.booking_type,                            -- NULL means the default booking type for the document type
    booking_category  text check(length(trim(booking_category)) > 0), -- A custom text sub category for the booking_type

    constraint document_category_booking_type_null check (
      (booking_type is null)
      or
      (document_type = 'INCOMING_INVOICE' or document_type = 'OUTGOING_INVOICE')
    ),

    description text,

    email_alias public.email_alias,
    -- constraint unique_document_type_email_alias unique(client_company_id, document_type, email_alias) where booking_type is null and booking_category is null,
    constraint valid_booking_category_and_email_alias check (
      (
        booking_category is null
        and
        email_alias is null
      )
      or -- email_alias only makes sense when booking_category is set
      (
        coalesce(booking_category, '') <> ''
        and
        coalesce(email_alias, '') <> ''
      )
    ),

    ignore_booking_type_paid_assumption boolean not null default false,
    -- payed              boolean,
    -- payed_cash         boolean,
    -- payed_bank_account bank_iban,
    -- payed_credit_card  credit_card_no,

    general_ledger_account_id uuid references public.general_ledger_account(id),


    -- used to override accounting items suggestions
    accounting_items_general_ledger_account_id uuid references public.general_ledger_account(id),
    constraint accounting_items_general_ledger_account_only_with_booking_type check (
      accounting_items_general_ledger_account_id is null
      or booking_type is not null
    ),

    -- used to override accounting items suggestions
    accounting_items_title trimmed_text,
    constraint accounting_items_title_only_with_booking_type check (
      accounting_items_title is null
      or booking_type is not null
    ),

    internal_number_mode public.document_category_internal_number_mode,
    internal_number_min  bigint,

    custom_extraction_service public.extraction_service, -- null means no customization, use default

    sort_index int not null default 0,

    updated_at updated_time not null,
    created_at created_time not null
);

comment on type public.document_category is 'Category which connects all document types to one.';

grant select, insert, update, delete on table public.document_category to domonda_user;
grant select on table public.document_category to domonda_wg_user;

create index document_category_booking_type_idx
  on public.document_category (booking_type);
create index document_category_general_ledger_account_id_idx
  on public.document_category (general_ledger_account_id);
create index document_category_document_type_idx
  on public.document_category (document_type);
create index document_category_client_company_id_idx
  on public.document_category (client_company_id);
create index document_category_accounting_items_general_ledger_account_id_idx
  on public.document_category (accounting_items_general_ledger_account_id);

-- Not null description has to be unique per client company

create unique index unique_document_category_description
  on public.document_category (client_company_id, description)
  where description is not null;

-- Identicalal combinations of client_company_id, document_type, booking_type, booking_category
-- need a description to distinguish them with (description is null) treated as one unique value

create unique index unique_document_category_document_type_description_null
  on public.document_category (client_company_id, document_type, (description is null))
  where booking_type is null and booking_category is null and description is null;

create unique index unique_document_category_document_type_booking_type_description_null
  on public.document_category (client_company_id, document_type, booking_type, (description is null))
  where booking_type is not null and booking_category is null and description is null;

create unique index unique_document_category_document_type_booking_category_description_null
  on public.document_category (client_company_id, document_type, booking_category, (description is null))
  where booking_type is null and booking_category is not null and description is null;

create unique index unique_document_category_document_type_booking_type_booking_category_description_null
  on public.document_category (client_company_id, document_type, booking_type, booking_category, (description is null))
  where booking_type is not null and booking_category is not null and description is null;


-- 8 combinations of nullable uniques for
--     client_company_id, document_type, booking_type, booking_category, email_alias:

create unique index unique_document_type_email_alias
  on public.document_category (client_company_id, document_type, email_alias)
  where booking_type is null and booking_category is null;

create unique index unique_document_type_booking_type_email_alias
  on public.document_category (client_company_id, document_type, booking_type, email_alias)
  where booking_type is not null and booking_category is null;

create unique index unique_document_type_booking_category_email_alias
  on public.document_category (client_company_id, document_type, booking_category, email_alias)
  where booking_type is null and booking_category is not null;

create unique index unique_document_type_booking_type_booking_category_email_alias
  on public.document_category (client_company_id, document_type, booking_type, booking_category, email_alias)
  where booking_type is not null and booking_category is not null;

-- (email_alias is null) is treated as single value per combination

create unique index unique_document_type_email_alias_null
  on public.document_category (client_company_id, document_type, (email_alias is null))
  where booking_type is null and booking_category is null and email_alias is null;

create unique index unique_document_type_booking_type_email_alias_null
  on public.document_category (client_company_id, document_type, booking_type, (email_alias is null))
  where booking_type is not null and booking_category is null and email_alias is null;

create unique index unique_document_type_booking_category_email_alias_null
  on public.document_category (client_company_id, document_type, booking_category, (email_alias is null))
  where booking_type is null and booking_category is not null and email_alias is null;

create unique index unique_document_type_booking_type_booking_category_email_alias_null
  on public.document_category (client_company_id, document_type, booking_type, booking_category, (email_alias is null))
  where booking_type is not null and booking_category is not null and email_alias is null;

----

create function public.client_company_uses_internal_number_mode(
  client_company public.client_company
) returns boolean as
$$
  select client_company.invoice_internal_number_count_up_mode
  or exists (
    select 1 from public.document_category
    where document_category.client_company_id = client_company.company_id
    and document_category.internal_number_mode is not null
  )
$$
language sql stable;

comment on function public.client_company_uses_internal_number_mode is '@notNull';

----

create function public.document_category_full_name(
  document_category public.document_category,
  "language"        public.language_code
) returns text as $$ -- {booking_type || document_type} - {description} [{booking_category}]
declare
  booking_type_name  text;
  document_type_name text;
begin
  case document_category.booking_type
  when 'CASH_BOOK' then
    if "language" = 'de'
    then
      booking_type_name := 'Kassa';
    else
      booking_type_name := 'Cash book';
    end if;
  when 'CLEARING_ACCOUNT' then
    if "language" = 'de'
    then
      booking_type_name := 'Verrechnungskonto';
    else
      booking_type_name := 'Clearing account';
    end if;
  else
    booking_type_name := null;
  end case;

  case document_category.document_type
  when 'INCOMING_INVOICE' then
    if "language" = 'de'
    then
      document_type_name := 'Eingangsrechnung';
    else
      document_type_name := 'Incoming invoice';
    end if;
  when 'OUTGOING_INVOICE' then
    if "language" = 'de'
    then
      document_type_name := 'Ausgangsrechnung';
    else
      document_type_name := 'Outgoing invoice';
    end if;
  when 'INCOMING_DUNNING_LETTER' then
    if "language" = 'de'
    then
      document_type_name := 'Eingehende Mahnung';
    else
      document_type_name := 'Incoming dunning letter';
    end if;
  when 'OUTGOING_DUNNING_LETTER' then
    if "language" = 'de'
    then
      document_type_name := 'Ausgehende Mahnung';
    else
      document_type_name := 'Outgoing dunning letter';
    end if;
  when 'INCOMING_DELIVERY_NOTE' then
    if "language" = 'de'
    then
      document_type_name := 'Eingehender Lieferschein';
    else
      document_type_name := 'Incoming delivery note';
    end if;
  when 'OUTGOING_DELIVERY_NOTE' then
    if "language" = 'de'
    then
      document_type_name := 'Ausgehender Lieferschein';
    else
      document_type_name := 'Outgoing delivery note';
    end if;
  when 'BANK_STATEMENT' then
    if "language" = 'de'
    then
      document_type_name := 'Bankauszug';
    else
      document_type_name := 'Bank statement';
    end if;
  when 'CREDITCARD_STATEMENT' then
    if "language" = 'de'
    then
      document_type_name := 'Kreditkartenabrechnung';
    else
      document_type_name := 'Credit card statement';
    end if;
  when 'FACTORING_STATEMENT' then
    if "language" = 'de'
    then
      document_type_name := 'Factoring Abrechnung';
    else
      document_type_name := 'Factoring statement';
    end if;
  when 'DOCUMENT_EXPORT_FILE' then
    if "language" = 'de'
    then
      document_type_name := 'Exportdokument';
    else
      document_type_name := 'Document export file';
    end if;
  when 'BANK_EXPORT_FILE' then
    if "language" = 'de'
    then
      document_type_name := 'Bankexport-Datei';
    else
      document_type_name := 'Bank export file';
    end if;
  when 'ACL_IMPORT_FILE' then
    if "language" = 'de'
    then
      document_type_name := 'ACL-Import-Datei';
    else
      document_type_name := 'ACL import file';
    end if;
  when 'CREDITCARD_IMPORT_FILE' then
    if "language" = 'de'
    then
      document_type_name := 'Kreditkarten-Import-Datei';
    else
      document_type_name := 'Credit card import file';
    end if;
  when 'BANK_ACCOUNT_IMPORT_FILE' then
    if "language" = 'de'
    then
      document_type_name := 'Bankkonto-Import-Datei';
    else
      document_type_name := 'Bank account import file';
    end if;
  when 'DMS_DOCUMENT' then
    if "language" = 'de'
    then
      document_type_name := 'DMS Dokument';
    else
      document_type_name := 'DMS Document';
    end if;
  else -- we use `else` instead of `when 'OTHER_DOCUMENT' then` because case statements need an else statement
    if "language" = 'de'
    then
      document_type_name := 'Sonstige Dokumente';
    else
      document_type_name := 'Other document';
    end if;
  end case;

  return coalesce(booking_type_name, document_type_name) ||
    coalesce((' - ' || document_category.description), '') ||
    coalesce((' [' || document_category.booking_category || ']'), '');
end
$$ language plpgsql immutable strict;
comment on function public.document_category_full_name is '@notNull';

create index document_category_full_name_en_idx on public.document_category ((public.document_category_full_name(document_category, 'en')));
create index document_category_full_name_de_idx on public.document_category ((public.document_category_full_name(document_category, 'de')));

----

create function public.document_category_full_name_wo_document_type(
  document_category public.document_category
) returns text as
$$
  -- {description} [{booking_category}]
  select trim(nullif(coalesce(document_category.description, '') || coalesce((' [' || document_category.booking_category || ']'), ''), ''))
$$
language sql stable strict;

----

create function public.derive_document_category_email_prefix(
  document_type public.document_type,
  booking_type  public.booking_type = null,
  email_alias   public.email_alias = null,
  "language"    language_code = 'de'
) returns text as
$$
  -- document_type[+booking_type][+email_alias]
  select
    (
      -- default or no-match fallbacks to german
      select
        case lower("language")
          when 'en' then english_alias
          else german_alias
        end
      from public.document_type_email_alias
      where "type" = derive_document_category_email_prefix.document_type
    ) || (
      coalesce(
        '+' || (
          -- default or no-match fallbacks to german
          select
            case lower("language")
              when 'en' then english_alias
              else german_alias
            end
          from public.booking_type_email_alias
          where "type" = derive_document_category_email_prefix.booking_type
        ),
        ''
      )
    ) || (
      coalesce(
        '+' || derive_document_category_email_prefix.email_alias,
        ''
      )
    )
$$
language sql stable;

----

create function public.document_category_email_prefix(
  document_category public.document_category,
  "language"        language_code = 'de'
) returns text as
$$
  select public.derive_document_category_email_prefix(
    document_category.document_type,
    document_category.booking_type,
    document_category.email_alias,
    "language"
  )
$$
language sql stable;

----

create function public.derive_document_category_email_address(
  client_company_id uuid,
  document_type     public.document_type,
  booking_type      public.booking_type = null,
  email_alias       public.email_alias = null,
  "language"        language_code = 'de'
) returns text as
$$
  select
    public.derive_document_category_email_prefix(
      derive_document_category_email_address.document_type,
      derive_document_category_email_address.booking_type,
      derive_document_category_email_address.email_alias,
      derive_document_category_email_address."language"
    ) || '+' || client_company.email_alias || '@domonda.com'
  from public.client_company
  where client_company.company_id = derive_document_category_email_address.client_company_id
$$
language sql stable;

----

create function public.document_category_email_address(
  document_category public.document_category,
  "language"        language_code = 'de'
) returns text as
$$
  select
    public.document_category_email_prefix(document_category, "language") || '+' || client_company.email_alias || '@domonda.com'
  from public.client_company
  where client_company.company_id = document_category.client_company_id
$$
language sql stable;

----

create function public.derive_document_category_booking_code(
  document_type public.document_type,
  booking_type  public.booking_type = null
) returns text as
$$
  select case coalesce(booking_type::text, document_type::text)
    when 'INCOMING_INVOICE' then 'ER'
    when 'OUTGOING_INVOICE' then 'AR'
    when 'INCOMING_DUNNING_LETTER' then 'EMAHN'
    when 'OUTGOING_DUNNING_LETTER' then 'MAHN'
    when 'INCOMING_DELIVERY_NOTE' then 'LS'
    when 'OUTGOING_DELIVERY_NOTE' then 'ALS'
    when 'BANK_STATEMENT' then 'BK'
    when 'CREDITCARD_STATEMENT' then 'KK'
    when 'FACTORING_STATEMENT' then 'FACTOR'
    when 'OTHER_DOCUMENT' then 'DOKUMENT'
    when 'DMS_DOCUMENT' then 'DMS_DOKUMENT'
    -- booking_type
    when 'CASH_BOOK' then 'KA'
    when 'CLEARING_ACCOUNT' then 'VK'
  end
$$
language sql immutable;

create function public.document_category_booking_code(
  document_category public.document_category
) returns text as -- NOTE: maybe use a enum?
$$
  select coalesce(
    document_category.booking_category,
    public.derive_document_category_booking_code(
      document_category.document_type,
      document_category.booking_type
    ),
    'OTHER'

    -- previously:
    -- case document_category.document_type
    --   when 'INCOMING_INVOICE' then 'ER'
    --   when 'OUTGOING_INVOICE' then 'AR'
    --   else 'OTHER' -- talk to Stafan about other derivations
    -- end
  )
$$
language sql immutable strict;

comment on function public.document_category_booking_code is '@notNull';

----

create function public.document_categories_by_ids(
    ids uuid[]
) returns setof public.document_category as $$
    select * from public.document_category where id = any(ids)
$$ language sql stable strict;
