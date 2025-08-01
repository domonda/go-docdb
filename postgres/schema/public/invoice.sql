create type public.invoice_payment_status as enum (
    'NOT_PAYABLE', -- for cases when the invoice needs to be ignored by the open-items filter
    'CREDITCARD',
    'CASH',
    'EXPENSES_PAID',
    'BANK',
    'PAYPAL',
    'TRANSFERWISE',
    'DIRECT_DEBIT'
);

-- json is easier to maintain and manipulate in Go (compared to postgres composite types)
-- see pkg/document/invoice/invoice.go#VATGroups
create domain public.invoice_vat_group as jsonb
    constraint vat_rate_exists check (
        value is null -- not null constraints should be on table columns
        or (
            -- TODO: will other fields always be provided by BluDelta?
            value->'vatRate' is not null
        )
    )
    constraint vat_rate_range check (
        value is null
        or (
            (value->>'vatRate')::float8 >= 0 -- zero vat is possible
            and (value->>'vatRate')::float8 < 100
        )
    )
    constraint net_or_vat_amount_exists check (
        value is null
        or (
          (value->>'netAmount')::float8 is not null
          or (value->>'vatAmount')::float8 is not null
        )
    );

----

create type public.ger_clause_35a_kind as enum (
	'MARGINAL_EMPLOYMENT', -- 1: Personalkosten für geringfügige Beschäftigungsverhältnisse im Privathaushalt
	'ENSURED_EMPLOYMENT',  -- 2: Personalkosten für sozialversicherungspflichtige Beschäftigungsverhältnisse im Privathaushalt
	'HOUSEHOLD_SERVICES',  -- 3: Haushaltsnahe Dienstleistungen, Hilfe im Haushalt
	'CRAFTSMAN_SERVICES'   -- 4: Handwerkerleistungen
);

----

create type public.invoice_xml_source as enum (
    'ebInterface',
    'UBL',
    'UN/CEFACT'
);

----

create table public.invoice (
    document_id uuid primary key references public.document(id) on delete cascade,
    number_id   serial unique,

    unresolved_issues      boolean not null default false, -- Unresolved issues from Abacus or detected by Domonda
    unresolved_issues_desc text[],                         -- Optional descriptions of unresolved issues

    -- deprecated (values moved to booked_by and booked_at respectively)
    accountant_lock_by text,        -- not null means accountant is working with the invoice, can't be changed by client
    accountant_lock_at timestamptz, -- not null means accountant is working with the invoice, can't be changed by client

    -- please use public.export(booking_export) whenever possible
    booked_by text,        -- not null means invoice has been booked and can't be changed anymore
    booked_at timestamptz, -- not null means invoice has been booked and can't be changed anymore
    constraint booked_at_and_by check((booked_at is null) = (booked_by is null)),

    -- NOTE: extracted partner name/vat_id/comp_reg_no/country are used only to hold the raw extracted
    -- partner details. These details are used later to find or create the actual
    -- partner company referenced by the partner_company_id foreign key
    extracted_partner_name           trimmed_text,
    extracted_partner_name_by        text,
    extracted_partner_vat_id         public.vat_id,
    extracted_partner_vat_id_by      text,
    extracted_partner_comp_reg_no    trimmed_text,
    extracted_partner_comp_reg_no_by text,
    extracted_partner_number         trimmed_text,
    extracted_partner_number_by      text,
    extracted_partner_country        public.country_code,
    extracted_partner_country_by     text,
    extracted_partner_email_addrs    text[],
    extracted_vat_groups             public.invoice_vat_group[],

    partner_company_id              uuid references public.partner_company(id),
    partner_company_id_confirmed_by text,
    partner_company_id_confirmed_at timestamptz,

    -- the address (holding the vatid) of the partner
    partner_company_location_id              uuid references public.company_location(id),
    partner_company_location_id_confirmed_by non_empty_text,
    partner_company_location_id_confirmed_at timestamptz,
    constraint partner_company_address_check check(partner_company_location_id is null or partner_company_id is not null),

    invoice_number              text check(length(trim(invoice_number)) > 0),
    invoice_number_confirmed_by text,
    invoice_number_confirmed_at timestamptz,

    order_number              non_empty_text,
    order_number_confirmed_by text,
    order_number_confirmed_at timestamptz,

    internal_number              text check(length(trim(internal_number)) > 0), -- Not unique on purpose!
    internal_number_confirmed_by text,
    internal_number_confirmed_at timestamptz,

    invoice_date              date,
    invoice_date_confirmed_by text,
    invoice_date_confirmed_at timestamptz,

    order_date              date,
    order_date_confirmed_by text,
    order_date_confirmed_at timestamptz,

    net              float8,
    net_confirmed_by text,
    net_confirmed_at timestamptz,
    constraint positive_net_check check(net >= 0),

    total              float8,
    total_confirmed_by text,
    total_confirmed_at timestamptz,
    constraint positive_total_check check(total >= 0),

    vat_percent              float8,
    vat_percent_confirmed_by text,
    vat_percent_confirmed_at timestamptz,
    vat_percentages          float8[],
    vat_amounts              float8[],

    -- percentage is 0-100 (needs division by 100 when using it)
    discount_percent              float8,
    discount_percent_confirmed_by text,
    discount_percent_confirmed_at timestamptz,

    -- discount amount
    discount_amount              float8,
    discount_amount_confirmed_by text,
    discount_amount_confirmed_at timestamptz,

    constraint discount_percent_or_amount_not_both_check check(
        (discount_percent is null and discount_amount is null) -- neither
        or (discount_percent is not null and discount_amount is null) -- only percent
        or (discount_percent is null and discount_amount is not null) -- only amount
    ),

    -- skonto = discount_until < today
    discount_until              date,
    discount_until_confirmed_by text,
    discount_until_confirmed_at timestamptz,

    currency               public.currency_code not null default 'EUR',
    currency_confirmed_by  text,
    currency_confirmed_at  timestamptz,

    conversion_rate          float8 check (conversion_rate > 0),
    conversion_rate_date     date, -- if the source is an UUID then the date represents the date of the modification
    conversion_rate_source   text, -- source can be of UUID type when the rate is manually entered

    goods_services              text check(length(trim(goods_services)) > 0),
    goods_services_confirmed_by text,
    goods_services_confirmed_at timestamptz,

    delivered_from              date,
    delivered_from_confirmed_by text,
    delivered_from_confirmed_at timestamptz,

    delivered_until              date,
    delivered_until_confirmed_by text,
    delivered_until_confirmed_at timestamptz,

    constraint delivered_until_must_be_exist_when_setting_delivered_from check(
        delivered_from is null
            or delivered_until is not null
    ),
    constraint delivered_from_is_before_until check(
        delivered_from is null
            or delivered_until is null
            or (delivered_from <= delivered_until)
    ),

    iban              public.bank_iban,
    iban_confirmed_by text,
    iban_confirmed_at timestamptz,
    iban_candidates   text[],

    bic              public.bank_bic,
    bic_confirmed_by text,
    bic_confirmed_at timestamptz,
    bic_candidates   text[],

    due_date              date,
    due_date_confirmed_by text,
    due_date_confirmed_at timestamptz,

    payment_status              public.invoice_payment_status, -- How the invoice was paid, selected by the user in the App UI
    payment_status_confirmed_by text,
    payment_status_confirmed_at timestamptz,

    payment_reference              trimmed_text, -- The reference text to be used for the invoice payment, entered by the user in the App UI
    payment_reference_confirmed_by text,
    payment_reference_confirmed_at timestamptz,

    pay_from_bank_account_id              uuid references public.bank_account(id),
    pay_from_bank_account_id_confirmed_by trimmed_text,
    pay_from_bank_account_id_confirmed_at timestamptz,

    paid_date              date, -- When the invoice was paid, entered by the user in the App UI
    paid_date_confirmed_by text,
    paid_date_confirmed_at timestamptz,

    credit_memo boolean not null default false,
    credit_memo_confirmed_by text,
    credit_memo_confirmed_at timestamptz,

    credit_memo_for_invoice_document_id uuid references public.invoice(document_id) on delete set null, -- TODO-db-21027 is set null the way it should be done?
    credit_memo_for_invoice_document_id_confirmed_by text,
    credit_memo_for_invoice_document_id_confirmed_at timestamptz,
    constraint credit_memo_for_invoice_check check(
        (credit_memo_for_invoice_document_id is null)
        or
        (credit_memo_for_invoice_document_id is not null and credit_memo) -- when set, credit_memo must be true
    ),

    override_partner_company_payment_preset    boolean not null default false,
    override_partner_company_payment_preset_by uuid references public.user(id) on delete set null,
    override_partner_company_payment_preset_at timestamptz,
    constraint by_exists_when_override_partner_company_payment_preset check (
        case
            when override_partner_company_payment_preset
            then override_partner_company_payment_preset_by is not null
            else true
        end
    ),
    constraint by_and_at_exists_when_override_partner_company_payment_preset check (
        case
            when override_partner_company_payment_preset_by is not null
            then override_partner_company_payment_preset_at is not null
            else true
        end
    ),

    partially_paid              boolean not null default false,
    partially_paid_confirmed_by uuid references public.user(id) on delete set null,
    partially_paid_confirmed_at timestamptz,

    constraint disallow_partially_paid_and_not_payable check(
        case when payment_status = 'NOT_PAYABLE'
        then not partially_paid
        else true
        end
    ),

    -- Delivery note numbers printed on the invoice,
    -- does not mean they have to exist in the DB
    delivery_note_numbers              text[], -- TODO add to public.document_field
    delivery_note_numbers_confirmed_by trimmed_text,
    delivery_note_numbers_confirmed_at timestamptz,

    open_items_number              trimmed_text, -- TODO add to public.document_field
    open_items_number_confirmed_by text,
    open_items_number_confirmed_at timestamptz,

    ger_clause_35a_net              float8 check (ger_clause_35a_net > 0), -- TODO add to public.document_field
    ger_clause_35a_net_confirmed_by text,
    ger_clause_35a_net_confirmed_at timestamptz,

    ger_clause_35a_total              float8 check (ger_clause_35a_total > 0), -- TODO add to public.document_field
    ger_clause_35a_total_confirmed_by text,
    ger_clause_35a_total_confirmed_at timestamptz,
    constraint ger_clause_35a_net_fits_total check(ger_clause_35a_net <= ger_clause_35a_total),

    ger_clause_35a_kind              public.ger_clause_35a_kind, -- TODO add to public.document_field
    ger_clause_35a_kind_confirmed_by text,
    ger_clause_35a_kind_confirmed_at timestamptz,

    -- DO NOT FORGET TO ADD NEW FIELDS TO public.document_field !

    updated_at updated_time not null,
    created_at created_time not null
);

comment on column public.invoice.payment_status is 'How the invoice was paid, selected by the user in the App UI. Use `Document.paymentStatus` to get a consolidated status including matched money transactions.';
comment on column public.invoice.paid_date is 'When the invoice was paid, entered by the user in the App UI.';
comment on column public.invoice.updated_at is 'Time of last update.';
comment on column public.invoice.created_at is 'Creation time of object.';
comment on column public.invoice.override_partner_company_payment_preset is 'Should the `Invoice` payment details take precedence over any `PartnerCompanyPaymentPreset`.';
comment on column public.invoice.ger_clause_35a_net is 'German real estate law clause 35a net amount relevant for real estate service invoices.';
comment on column public.invoice.ger_clause_35a_total is 'German real estate law clause 35a total amount relevant for real estate service invoices.';
comment on column public.invoice.ger_clause_35a_kind is 'German real estate law clause 35a kind. Can be "MARGINAL_EMPLOYMENT", "ENSURED_EMPLOYMENT", "HOUSEHOLD_SERVICES", "CRAFTSMAN_SERVICES".';

comment on constraint positive_net_check on public.invoice is '@error The net amount must be positive';
comment on constraint positive_total_check on public.invoice is '@error The total amount must be positive';
comment on constraint partner_company_address_check on public.invoice is '@error A partner company must be set with the location';

grant select, update on table public.invoice to domonda_user;
grant select on table public.invoice to domonda_wg_user; -- TODO: add RLS policies for UPDATE

create index invoice_invoice_number_idx on public.invoice (invoice_number);
create index invoice_order_number_idx on public.invoice (order_number);
create index invoice_invoice_date_idx on public.invoice (invoice_date);
create index invoice_order_date_idx on public.invoice (order_date);
create index invoice_due_date_idx on public.invoice (due_date);
create index invoice_partner_company_id_idx on public.invoice (partner_company_id);
create index invoice_partner_company_location_id_idx on public.invoice (partner_company_location_id);
create index invoice_credit_memo_idx on public.invoice (credit_memo);
create index invoice_credit_memo_for_invoice_document_id_idx on public.invoice (credit_memo_for_invoice_document_id);
create index invoice_total_idx on public.invoice (total);
create index invoice_accountant_lock_by_idx on public.invoice (accountant_lock_by);
create index invoice_accountant_lock_at_idx on public.invoice (accountant_lock_at);
create index invoice_accountant_lock_at_not_null_idx on public.invoice ((accountant_lock_at is not null));
create index invoice_booked_by_idx on public.invoice (booked_by);
create index invoice_booked_at_idx on public.invoice (booked_at);
create index invoice_booked_at_not_null_idx on public.invoice ((booked_at is not null));
create index invoice_override_partner_company_payment_preset_idx on public.invoice (override_partner_company_payment_preset);
create index invoice_partially_paid_idx on public.invoice (partially_paid);
create index invoice_payment_status_idx on public.invoice (payment_status);
create index invoice_delivery_note_numbers_idx on public.invoice (delivery_note_numbers);

----

create function public.invoices_by_document_ids(
    document_ids uuid[]
) returns setof public.invoice as
$$
    select * from public.invoice where (document_id = any(document_ids))
$$
language sql stable strict;

comment on function public.invoices_by_document_ids is 'Returns `Invoices` by their `documentId`.';

----

create function public.invoice_partner_name(
    invoice public.invoice
) returns text as $$
    select partner_company.derived_name
    from public.partner_company
    where id = invoice.partner_company_id
$$ language sql stable strict;

comment on function public.invoice_partner_name is 'Partner name from the linked partner company.';

----

create function public.invoice_partner_vat_id_no(
    invoice public.invoice
) returns public.vat_id as $$
    select vat_id_no
    from public.company_location
    where id = invoice.partner_company_location_id
$$ language sql stable strict;

comment on function public.invoice_partner_vat_id_no is 'Partner VAT-ID number derived from the linked location.';

----

create function public.invoice_partner_name_with_vat_id_no(
    invoice public.invoice
) returns text as $$
    select coalesce(
        public.invoice_partner_name(invoice) || ' ' || public.invoice_partner_vat_id_no(invoice)::text,
        public.invoice_partner_name(invoice)
    )
$$ language sql stable strict;

comment on function public.invoice_partner_name_with_vat_id_no is 'Partner name with VAT-ID number from the linked partner company. If not VAT-ID number is available, it will return just the name.';

----

create function public.incoming_invoices_by_document_ids(
    document_ids uuid[]
) returns setof public.invoice as
$$
    select i.* from public.invoice as i
        inner join (
            public.document as d
            inner join public.document_category as dc on (dc.id = d.category_id and dc.document_type = 'INCOMING_INVOICE')
        ) on (d.id = i.document_id)
    where (i.document_id = any(document_ids))
$$
language sql stable strict;

comment on function public.incoming_invoices_by_document_ids is 'Returns `Invoices` of `INCOMING_INVOICE` document type by their `documentId`.';

----

create function public.incoming_invoices_and_outgoing_credit_memos_by_document_ids(
    document_ids uuid[]
) returns setof public.invoice as
$$
    select invoice.* from public.invoice
        inner join public.document on document.id = invoice.document_id
        inner join public.document_category on document_category.id = document.category_id
    where invoice.document_id = any(document_ids)
    and ((
        document_category.document_type = 'INCOMING_INVOICE'
        and not invoice.credit_memo
    ) or (
        document_category.document_type = 'OUTGOING_INVOICE'
        and invoice.credit_memo
    ))
$$
language sql stable strict;

comment on function public.incoming_invoices_and_outgoing_credit_memos_by_document_ids is 'Returns `Invoices` of `INCOMING_INVOICE` document type which are not `creditMemo` and `OUTGOING_INVOICE` document type which are `creditMemo` by their `documentId`.';

create function public.outgoing_invoices_and_not_credit_memos_by_document_ids(
    document_ids uuid[]
) returns setof public.invoice as
$$
    select invoice.* from public.invoice
        inner join public.document on document.id = invoice.document_id
        inner join public.document_category on document_category.id = document.category_id
    where invoice.document_id = any(document_ids)
    and document_category.document_type = 'OUTGOING_INVOICE'
    and not invoice.credit_memo
$$
language sql stable strict;

comment on function public.outgoing_invoices_and_not_credit_memos_by_document_ids is 'Returns `Invoices` of `OUTGOING_INVOICE` document type which are not `creditMemo`s by their `documentId`.';

----

create function public.invoice_duplicate_invoices(
    invoice public.invoice
) returns setof public.invoice as
$$
    with invoice_document as (
        select client_company_id from public.document where id = invoice.document_id
    )
    select i.* from
        invoice_document,
        public.invoice as i
            inner join public.document as d on d.id = i.document_id
    where not d.superseded
    and d.client_company_id = invoice_document.client_company_id
    and i.document_id <> invoice.document_id
    and i.credit_memo = invoice.credit_memo
    and (i.invoice_number is not null) and (i.invoice_number = invoice.invoice_number)
    and (i.invoice_date is not null) and (i.invoice_date = invoice.invoice_date)
    and (i.total is not null) and (i.total = invoice.total)
    and (i.partner_company_id is not null) and (i.partner_company_id = invoice.partner_company_id)
$$
language sql stable;

comment on function public.invoice_duplicate_invoices is 'Finds duplicate `Invoices` matched by `creditMemo`, `invoiceNumber`, `invoiceDate`, `total` and the `partnerCompany`.';

----

create function public.invoice_has_duplicate_invoices(
    invoice public.invoice
) returns boolean as
$$
    select exists (select from public.invoice_duplicate_invoices(invoice))
$$
language sql stable;

comment on function public.invoice_has_duplicate_invoices is 'Checks if the `Invoices` has duplicates.';

----

create function public.invoice_partner_account(
    invoice public.invoice
) returns public.partner_account as
$$
    select pa.* from public.partner_account as pa
        inner join public.partner_company as pc on (pc.id = pa.partner_company_id) and (pc.id = invoice.partner_company_id)
        inner join (public.document as d
            inner join public.document_category as dc on (dc.id = d.category_id)
        ) on (d.id = invoice.document_id)
    where dc.booking_type is null
        and (pa.currency is null or pa.currency = invoice.currency)
        and (
            case
                -- vendor
                when dc.document_type = 'INCOMING_INVOICE' then (pa.type = 'VENDOR')
                -- client
                when dc.document_type = 'OUTGOING_INVOICE' then (pa.type = 'CLIENT')
            end
        )
    order by pa.currency asc nulls last
    limit 1
$$
language sql stable;

comment on function public.invoice_partner_account is 'Returns a `PartnerAccount` for the invoice type and currency if the document category booking type is not a clearing account or cash book.';

----

create function public.invoice_general_ledger_account(
    invoice public.invoice
) returns public.general_ledger_account as
$$
    select general_ledger_account.* from public.general_ledger_account
        inner join (
            public.document
            inner join public.document_category on (document_category.id = document.category_id)
        ) on (document.id = invoice.document_id)
    where document_category.booking_type is not null
    and general_ledger_account.id = document_category.general_ledger_account_id
$$
language sql stable;

comment on function public.invoice_general_ledger_account is 'Returns a `GeneralLedgerAccount` if the document category of the invoice has defined one.';

----

create function public.invoice_account_number(
    invoice public.invoice
) returns account_no as
$$
    select coalesce(
        -- if the document category booking type is not a clearing account or cash book
        (public.invoice_partner_account(invoice)).number,
        -- if the document category of the invoice has defined one
        (public.invoice_general_ledger_account(invoice)).number
    )
$$
language sql stable;

comment on function public.invoice_account_number is 'Returns the account number (string) of the invoice partner account for the invoice type and currency if the document category booking type is not a clearing account or cash book, or the document category general ledger account if the category has defined one.';

----

create function public.invoice_signed_total(
    invoice public.invoice
) returns float8 as
$$
    -- calculate signed invoice amount
    select case
        -- debit
        when (document_category.document_type = 'INCOMING_INVOICE' and (not invoice.credit_memo))
            or (document_category.document_type = 'OUTGOING_INVOICE' and invoice.credit_memo)
        then invoice.total * -1
        -- credit
        else invoice.total
    end
    from public.document
        inner join public.document_category on document_category.id = document.category_id
    where document.id = invoice.document_id
$$
language sql stable
security definer;

comment on function public.invoice_signed_total is 'The signed total of the given `Invoice` looking at the `Document.Category.documentType` and `Invoice.creditMemo`.';

----

create function public.invoice_signed_net(
    invoice public.invoice
) returns float8 as
$$
    select
        case
            when (invoice.net <> 0) and ((
                dc.document_type = 'INCOMING_INVOICE' and not invoice.credit_memo
            ) or (
                dc.document_type = 'OUTGOING_INVOICE' and invoice.credit_memo
            )) then (abs(invoice.net) * -1)
            else abs(invoice.net)
        end
    from public.document as d
        inner join public.document_category as dc on dc.id = d.category_id
    where d.id = invoice.document_id
$$
language sql stable;

comment on function public.invoice_signed_net is 'The signed net of the given `Invoice` looking at the `Document.Category.documentType` and `Invoice.creditMemo`.';

----

create function public.invoice_converted_total(
    invoice public.invoice
) returns float8 as
$$
    select abs(invoice.total) / coalesce(invoice.conversion_rate, 1.0)
$$
language sql immutable;

comment on function public.invoice_converted_total is 'The absolute (unsigned) total of the invoice in EUR';

----

create function public.invoice_converted_total_with_discount(
    invoice public.invoice
) returns float8 as
$$
    select (abs(invoice.total) / coalesce(invoice.conversion_rate, 1.0))
      - coalesce(
          (abs(invoice.total) / coalesce(invoice.conversion_rate, 1.0))
          * (invoice.discount_percent / 100), -- discount_percent
          (abs(invoice.total) / coalesce(invoice.conversion_rate, 1.0))
          - invoice.discount_amount, -- discount_amount
        0)
$$
language sql immutable;

comment on function public.invoice_converted_total_with_discount is 'The absolute (unsigned) total of the invoice in EUR minus optional discount percent';

----

create function public.invoice_converted_signed_total(
    invoice public.invoice
) returns float8 as
$$
    select public.invoice_signed_total(invoice) / coalesce(invoice.conversion_rate, 1)
$$
language sql stable;

create function public.invoice_converted_net(
    invoice public.invoice
) returns float8 as
$$
    select abs(invoice.net) / coalesce(invoice.conversion_rate, 1)
$$
language sql immutable;

create function public.invoice_converted_signed_net(
    invoice public.invoice
) returns float8 as
$$
    select public.invoice_signed_net(invoice) / coalesce(invoice.conversion_rate, 1)
$$
language sql stable;

----

create function public.invoice_accounting_currency(
    invoice public.invoice
) returns public.currency_code as
$$
    select client_company.accounting_currency
    from public.client_company
        inner join public.document on document.id = invoice.document_id
    where client_company.company_id = document.client_company_id
$$
language sql stable;

comment on function public.invoice_accounting_currency is E'@notNull\nAccounting currency of the invoice''s client company.';

----

create function public.invoice_is_foreign_currency(
    invoice public.invoice
) returns boolean as
$$
    select invoice.currency <> public.invoice_accounting_currency(invoice)
$$
language sql stable;

comment on function public.invoice_is_foreign_currency is 'Invoice currency is different from the accounting currency of the client company.';

----

create function public.invoice_vat_amount(
    invoice public.invoice
) returns float8 as
$$
    select round((abs(invoice.total) - abs(invoice.net))::numeric, 2)::float8
$$
language sql immutable strict;

comment on function public.invoice_vat_amount is 'Absolute VAT amount calculated by substracting `net` from `total`.';

----

create function public.invoice_has_unresolved_issues(
    inv public.invoice
) returns boolean as
$$
    select inv.unresolved_issues
$$
language sql stable;

comment on function public.invoice_has_unresolved_issues is 'Returns if a document has unresolved issues, which need further action';

----

create function public.invoice_booking_code(
    inv public.invoice
) returns text as
$$
    select public.document_category_booking_code(cat)
    from public.document_category as cat
    inner join public.document as doc on doc.id = inv.document_id
    where cat.id = doc.category_id
$$
language sql stable;

comment on function public.invoice_booking_code is 'Booking-code of the invoice document-category';

----

create function public.dunn_invoice(
  invoice_document_id uuid,
  metadata            text
) returns void as
$$
declare
  invoice_client_company_id uuid := (select client_company_id from public.document where id = invoice_document_id);
  user_language             language_code := (select "language" from private.current_user());
  dunned_tag_name           text := 'Dunned';
  dunned_tag                record;
begin
  if user_language is null then
    if user_language = 'de' then
        raise exception 'Authentifizierungsfehler.';
    end if;
    raise exception 'Authentication error.';
  end if;

  if not (public.is_company_feature_active('DUNNING_SERVICE', invoice_client_company_id)) then
    if user_language = 'de' then
        raise exception 'Diese Funktion ist für Ihr Unternehmen nicht aktiviert. Bitte wenden Sie sich an den Support.';
    end if;
    raise exception 'This feature is not activated for your company. Please contact support.';
  end if;

  if not (select public.invoice_can_dunn(invoice) from public.invoice where document_id = dunn_invoice.invoice_document_id) then
    if user_language = 'de' then
        raise exception 'Diese Rechnung kann nicht gemahnt werden.';
    end if;
    raise exception 'This invoice cannot be dunned.';
  end if;

  -- prepare tag
  select
    * into dunned_tag
  from public.client_company_tag
  where client_company_tag.client_company_id = invoice_client_company_id and client_company_tag.tag = dunned_tag_name;
  if dunned_tag is null then
    -- create tag if it does not exist
    insert into public.client_company_tag (id, client_company_id, tag)
      values (uuid_generate_v4(), invoice_client_company_id, dunned_tag_name)
    returning * into dunned_tag;
  else
    -- check if document is already tagged for existing tag
    if exists (select 1 from public.document_tag where client_company_tag_id = dunned_tag.id and document_id = dunn_invoice.invoice_document_id) then
        if user_language = 'de' then
            raise exception 'Diese Rechnung ist bereits gemahnt! Wenn Sie es erneut mahnen möchten, entfernen Sie zuerst das Tag "Dunned".';
        end if;
        raise exception 'This invoice is already dunned! If you want to dunn it again, please remove the "Dunned" tag first.';
    end if;
  end if;

  -- send email
  insert into worker.job (
    "type",
    payload,
    priority,
    origin,
    max_retry_count
  ) values (
    'SEND_MAIL',
    jsonb_build_object(
      'to', 'support@domonda.com',
      'templateType', 'DUNN_INVOICE',
      'templateLang', 'DE',
      'templateData', jsonb_build_object(
        'CompanyName', (select public.company_brand_name_or_name(company) from public.company where id = invoice_client_company_id),
        'UserName', (select public.user_full_name(cu) from private.current_user() as cu),
        'InvoiceDocumentID', dunn_invoice.invoice_document_id,
        'Metadata', dunn_invoice.metadata
      )
    ),
    0,
    'rule.dunn_invoice()',
    3
  );

  -- tag invoice
  insert into public.document_tag (client_company_tag_id, document_id)
    values (dunned_tag.id, dunn_invoice.invoice_document_id);
end
$$
language plpgsql volatile security definer;

----

-- true => has
-- false => doesnt have
-- null => does have a partner at all
create function public.invoice_partner_has_payment_preset(
    invoice public.invoice
) returns boolean as $$
    select not invoice.credit_memo and not (partner_company_payment_preset is null)
    from public.partner_company
        left join public.partner_company_payment_preset
        on partner_company_payment_preset.partner_company_id = partner_company.id
        and (
            partner_company_payment_preset.currency = invoice.currency
            or partner_company_payment_preset.currency is null
        )
    where partner_company.id = invoice.partner_company_id
$$ language sql stable strict;

----

create function public.invoice_payment_iban(
    invoice public.invoice
) returns public.bank_iban as $$
    select case
        when not invoice.override_partner_company_payment_preset and public.invoice_partner_has_payment_preset(invoice)
        then (public.primary_or_newest_currency_payment_preset_for_partner_company(invoice.partner_company_id, invoice.currency)).iban
        else invoice.iban
    end
$$ language sql stable strict;

----

create function public.invoice_payment_bic(
    invoice public.invoice
) returns public.bank_bic as $$
    select case
        when not invoice.override_partner_company_payment_preset and public.invoice_partner_has_payment_preset(invoice)
        then (public.primary_or_newest_currency_payment_preset_for_partner_company(invoice.partner_company_id, invoice.currency)).bic
        else invoice.bic
    end
$$ language sql stable strict;

----

create function public.invoice_payment_currency(
    invoice public.invoice
) returns public.currency_code as $$
    select case
        when not invoice.override_partner_company_payment_preset and public.invoice_partner_has_payment_preset(invoice)
        then coalesce((public.primary_or_newest_currency_payment_preset_for_partner_company(invoice.partner_company_id, invoice.currency)).currency, invoice.currency)
        else invoice.currency
    end
$$ language sql stable strict;
comment on function public.invoice_payment_currency is E'@notNull\nBecause the `currency` field on the `Invoice` is not nullable.';

----

create function public.invoice_payment_purpose(
    invoice public.invoice
) returns text as $$
    -- prepend the partner preset payment purpose
    select case
        when not invoice.override_partner_company_payment_preset and public.invoice_partner_has_payment_preset(invoice)
        then coalesce(
            (public.primary_or_newest_currency_payment_preset_for_partner_company(invoice.partner_company_id, invoice.currency)).purpose_prefix,
            ''
        ) || coalesce(invoice.payment_reference, invoice.invoice_number)
        else coalesce(invoice.payment_reference, invoice.invoice_number)
    end
$$ language sql stable strict;

----

create function public.invoice_payment_due_date(
    invoice public.invoice
) returns date as $$
    select case
        when not invoice.override_partner_company_payment_preset and public.invoice_partner_has_payment_preset(invoice)
        then (invoice.invoice_date + interval '1 day' * (public.primary_or_newest_currency_payment_preset_for_partner_company(invoice.partner_company_id, invoice.currency)).due_date_in_days)::date
        else invoice.due_date
    end
$$ language sql stable strict;

----

create function public.invoice_payment_overdue(
    invoice public.invoice
) returns boolean as $$
    select current_date <= public.invoice_payment_due_date(invoice)
$$ language sql stable strict;

----

create function public.invoice_payment_paid_date(
    invoice public.invoice
) returns date as $$
    -- TODO: use max instead of min? when working with partial paymants, the LAST payment completes the invoice
    select coalesce(
        (
            select min(coalesce(money_transaction.value_date, money_transaction.booking_date))
            from public.document_money_transaction
                inner join public.money_transaction on money_transaction.id = document_money_transaction.money_transaction_id
            where document_money_transaction.document_id = invoice.document_id
        ),
        (
            select min(created_at)::date
            from public.bank_payment
            where bank_payment.document_id = invoice.document_id
            and status = 'FINISHED'
        ),
        invoice.paid_date
    )
$$ language sql stable strict;

----

create function public.invoice_payment_discount_due_date(
    invoice public.invoice
) returns date as $$
    select case
        when not invoice.override_partner_company_payment_preset and public.invoice_partner_has_payment_preset(invoice)
        then (invoice.invoice_date + interval '1 day' * (public.primary_or_newest_currency_payment_preset_for_partner_company(invoice.partner_company_id, invoice.currency)).discount_due_date_in_days)::date
        else invoice.discount_until
    end
$$ language sql stable strict;

----

create function public.invoice_payment_discount_still_eligible(
    invoice public.invoice
) returns boolean as $$
    select case
        when (
            public.invoice_payment_discount_due_date(invoice) is null
            or (public.invoice_payment_paid_date(invoice) is null and public.invoice_payment_discount_due_date(invoice) >= current_date)
            or (not (public.invoice_payment_paid_date(invoice) is null) and public.invoice_payment_discount_due_date(invoice) >= public.invoice_payment_paid_date(invoice))
        ) then true
        else false
    end
$$ language sql stable strict;

----

create function public.invoice_payment_discount_percent(
    invoice public.invoice
) returns float8 as $$
    select case
        when not invoice.override_partner_company_payment_preset and public.invoice_partner_has_payment_preset(invoice)
        then (public.primary_or_newest_currency_payment_preset_for_partner_company(invoice.partner_company_id, invoice.currency)).discount_percent
        else invoice.discount_percent
    end
$$ language sql stable strict;

create function public.invoice_payment_discount_amount(
    invoice public.invoice
) returns float8 as $$
    select case
        when not invoice.override_partner_company_payment_preset and public.invoice_partner_has_payment_preset(invoice)
        then (public.primary_or_newest_currency_payment_preset_for_partner_company(invoice.partner_company_id, invoice.currency)).discount_amount
        else invoice.discount_amount
    end
$$ language sql stable strict;

create function public.invoice_payment_discount_net_amount(
    invoice public.invoice
) returns float8 as $$
    select invoice.net * public.invoice_payment_discount_percent(invoice) / 100
$$ language sql stable strict;

create function public.invoice_payment_discount_total_amount(
    invoice public.invoice
) returns float8 as $$
    select invoice.total * public.invoice_payment_discount_percent(invoice) / 100
$$ language sql stable strict;

create function public.invoice_total_with_payment_discount(
    invoice public.invoice
) returns float8 as $$
    select invoice.total - coalesce(
        invoice.total * (public.invoice_payment_discount_percent(invoice) / 100), -- discount_percent
        public.invoice_payment_discount_amount(invoice), -- discount_amount
        0
    )
$$ language sql stable;

create function public.invoice_converted_total_with_payment_discount(
    invoice public.invoice
) returns float8 as $$
    select (invoice.total / coalesce(invoice.conversion_rate, 1))
      - coalesce(
          (invoice.total / coalesce(invoice.conversion_rate, 1))
          * (public.invoice_payment_discount_percent(invoice) / 100), -- discount_percent
          public.invoice_payment_discount_amount(invoice), -- discount_amount
        0)
$$ language sql stable;

create function public.invoice_converted_signed_total_with_payment_discount(
    invoice public.invoice
) returns float8 as $$
    select (public.invoice_signed_total(invoice) / coalesce(invoice.conversion_rate, 1))
    - coalesce(
        (public.invoice_signed_total(invoice) / coalesce(invoice.conversion_rate, 1))
        * (public.invoice_payment_discount_percent(invoice) / 100), -- discount_percent
        (select case when (public.invoice_signed_total(invoice) < 0)
            then public.invoice_payment_discount_amount(invoice) * -1 -- incoming invoice
            else public.invoice_payment_discount_amount(invoice) -- outgoing invoice
        end), -- discount_amount
    0)
$$ language sql stable;

create function public.invoice_converted_discounted_total(
    invoice public.invoice
) returns float8 as $$
    select case
        when (
            public.invoice_payment_discount_due_date(invoice) is null
            or (public.invoice_payment_paid_date(invoice) is null and public.invoice_payment_discount_due_date(invoice) >= current_date)
            or (not (public.invoice_payment_paid_date(invoice) is null) and public.invoice_payment_discount_due_date(invoice) >= public.invoice_payment_paid_date(invoice))
        )
        then public.invoice_converted_total_with_payment_discount(invoice)
        else public.invoice_converted_total(invoice)
    end
$$ language sql stable;

create function public.invoice_converted_signed_discounted_total(
    invoice public.invoice
) returns float8 as $$
    select case
        when (
            public.invoice_payment_discount_due_date(invoice) is null
            or (public.invoice_payment_paid_date(invoice) is null and public.invoice_payment_discount_due_date(invoice) >= current_date)
            or (not (public.invoice_payment_paid_date(invoice) is null) and public.invoice_payment_discount_due_date(invoice) >= public.invoice_payment_paid_date(invoice))
        )
        then public.invoice_converted_signed_total_with_payment_discount(invoice)
        else public.invoice_converted_signed_total(invoice)
    end
$$ language sql stable;

----

create function public.invoice_title(
    invoice public.invoice
) returns text as $$
    select coalesce(
        coalesce(
            public.invoice_partner_name(invoice) || ': ' || invoice.invoice_number,
            public.invoice_partner_name(invoice),
            invoice.invoice_number),
        (select coalesce(
            document.title,
            document.name)
        from public.document
        where document.id = invoice.document_id)
    )
$$ language sql stable
-- title is ok. especially in cases of linked credit-notes, where the
-- user might have access to the invoice, but not to the linked credit-note.
-- "security definer" allows at least a title to be displayed
security definer;

comment on function public.invoice_title is E'@notNull\nTitle of the `Invoice` properly derived from its data.';

create function public.invoice_has_unverified_iban(
    invoice public.invoice
) returns boolean as $$
    select invoice.iban_candidates is not null
    and invoice.payment_status is distinct from 'NOT_PAYABLE'
    and not invoice.credit_memo
    and document_category.document_type is distinct from 'OUTGOING_INVOICE'
    and exists (
        select from public.partner_company
        where partner_company.id = invoice.partner_company_id
        and not paid_with_direct_debit
    ) and (
        (
            invoice.override_partner_company_payment_preset
            and not invoice.iban = any(invoice.iban_candidates)
        ) or (
            not invoice.override_partner_company_payment_preset
            and (
                not public.invoice_partner_has_payment_preset(invoice)
                or not exists (
                    select from public.partner_company_payment_preset
                    where partner_company_payment_preset.partner_company_id = invoice.partner_company_id
                    and partner_company_payment_preset.iban = any(invoice.iban_candidates)
                )
            )
        )
    )
    from public.document
        inner join public.document_category on document_category.id = document.category_id
        inner join public.client_company on client_company.company_id = document.client_company_id
    where document.id = invoice.document_id
    and not client_company.disable_unverified_iban_check
$$ language sql stable;

create function public.override_partner_company_payment_preset_on_invoice(
    invoice_document_id uuid
) returns public.invoice as $$
    update public.invoice
        set
            override_partner_company_payment_preset=true,
            override_partner_company_payment_preset_by=private.current_user_id(),
            override_partner_company_payment_preset_at=now(),
            updated_at=now()
    where invoice.document_id = override_partner_company_payment_preset_on_invoice.invoice_document_id
    returning *
$$ language sql volatile strict;

create function private.log_invoice_override_partner_company_payment_preset()
returns trigger as $$
begin
    if private.current_user_id() is not null
    then
        insert into public.document_log (document_id, "type", user_id, created_at)
        values (
            NEW.document_id,
            'OVERRIDE_PARTNER_PAYMENT_PRESET',
            NEW.override_partner_company_payment_preset_by,
            NEW.override_partner_company_payment_preset_at
        );
    end if;
    return NEW;
end
$$ language plpgsql volatile security definer;

create trigger log_invoice_override_partner_company_payment_preset_trigger
    after update on public.invoice
    for each row
    when (
        NEW.override_partner_company_payment_preset
        and (
            OLD.override_partner_company_payment_preset is distinct from NEW.override_partner_company_payment_preset
            or OLD.override_partner_company_payment_preset_by is distinct from NEW.override_partner_company_payment_preset_by
            or OLD.override_partner_company_payment_preset_at is distinct from NEW.override_partner_company_payment_preset_at
        )
    )
    execute procedure private.log_invoice_override_partner_company_payment_preset();

----

create function public.invoice_ger_clause_35a_detected(
    invoice public.invoice
) returns boolean as $$
    select false
$$ language sql immutable strict;
comment on function public.invoice_ger_clause_35a_detected is '@notNull';

----

create function public.invoice_credit_memos_total_with_payment_discount_sum(
    invoice public.invoice
) returns float8 as $$
    select sum(public.invoice_total_with_payment_discount(credit_memo_invoice))
    from public.invoice as credit_memo_invoice
    where credit_memo_invoice.credit_memo_for_invoice_document_id = invoice.document_id
$$ language sql stable strict;

create function public.invoice_credit_memos_converted_signed_discounted_total_sum(
    invoice public.invoice
) returns float8 as $$
    select sum(public.invoice_converted_signed_discounted_total(credit_memo_invoice))
    from public.invoice as credit_memo_invoice
    where credit_memo_invoice.credit_memo_for_invoice_document_id = invoice.document_id
$$ language sql stable strict;

----

create function public.invoice_money_transactions_amount_sum(
    invoice public.invoice
) returns float8 as $$
    select sum(money_transaction.amount)
    from public.document_money_transaction
        inner join public.money_transaction on money_transaction.id = document_money_transaction.money_transaction_id
    where document_money_transaction.document_id = invoice.document_id
$$ language sql stable strict;

create function public.invoice_money_transactions_signed_amount_sum(
    invoice public.invoice
) returns float8 as $$
    select sum(public.money_transaction_signed_amount(money_transaction))
    from public.document_money_transaction
        inner join public.money_transaction on money_transaction.id = document_money_transaction.money_transaction_id
    where document_money_transaction.document_id = invoice.document_id
$$ language sql stable strict;

----

create function public.invoice_open_amount(
    invoice public.invoice
) returns float8 as $$
    with open_amount as (
        select public.invoice_converted_signed_discounted_total(invoice)
        - coalesce(public.invoice_credit_memos_converted_signed_discounted_total_sum(invoice) * -1, 0)
        - coalesce(public.invoice_money_transactions_signed_amount_sum(invoice), 0) as amount
    )
    -- do not overcompensate, if the amount is reached, show 0
    select
        case when
            (public.invoice_converted_signed_discounted_total(invoice) < 0 and open_amount.amount < 0) -- incoming invoice
            or (public.invoice_converted_signed_discounted_total(invoice) > 0 and open_amount.amount > 0) -- outgoing invoice
            then open_amount.amount
            else 0
        end
    from open_amount
$$ language sql stable strict;


----

create function public.invoice_values_confirmed_by(inv public.invoice) returns setof text
language plpgsql immutable strict as $$
begin
    if inv.invoice_number_confirmed_by is not null then
        return next inv.invoice_number_confirmed_by::text;
    end if;
    if inv.partner_company_id_confirmed_by is not null then
        return next inv.partner_company_id_confirmed_by::text;
    end if;
    if inv.partner_company_location_id_confirmed_by is not null then
        return next inv.partner_company_location_id_confirmed_by::text;
    end if;
    if inv.invoice_number_confirmed_by is not null then
        return next inv.invoice_number_confirmed_by::text;
    end if;
    if inv.order_number_confirmed_by is not null then
        return next inv.order_number_confirmed_by::text;
    end if;
    if inv.internal_number_confirmed_by is not null then
        return next inv.internal_number_confirmed_by::text;
    end if;
    if inv.invoice_date_confirmed_by is not null then
        return next inv.invoice_date_confirmed_by::text;
    end if;
    if inv.order_date_confirmed_by is not null then
        return next inv.order_date_confirmed_by::text;
    end if;
    if inv.net_confirmed_by is not null then
        return next inv.net_confirmed_by::text;
    end if;
    if inv.total_confirmed_by is not null then
        return next inv.total_confirmed_by::text;
    end if;
    if inv.vat_percent_confirmed_by is not null then
        return next inv.vat_percent_confirmed_by::text;
    end if;
    if inv.discount_percent_confirmed_by is not null then
        return next inv.discount_percent_confirmed_by::text;
    end if;
    if inv.discount_amount_confirmed_by is not null then
        return next inv.discount_amount_confirmed_by::text;
    end if;
    if inv.discount_until_confirmed_by is not null then
        return next inv.discount_until_confirmed_by::text;
    end if;
    if inv.currency_confirmed_by is not null then
        return next inv.currency_confirmed_by::text;
    end if;
    if inv.goods_services_confirmed_by is not null then
        return next inv.goods_services_confirmed_by::text;
    end if;
    if inv.delivered_from_confirmed_by is not null then
        return next inv.delivered_from_confirmed_by::text;
    end if;
    if inv.delivered_until_confirmed_by is not null then
        return next inv.delivered_until_confirmed_by::text;
    end if;
    if inv.iban_confirmed_by is not null then
        return next inv.iban_confirmed_by::text;
    end if;
    if inv.bic_confirmed_by is not null then
        return next inv.bic_confirmed_by::text;
    end if;
    if inv.due_date_confirmed_by is not null then
        return next inv.due_date_confirmed_by::text;
    end if;
    if inv.payment_status_confirmed_by is not null then
        return next inv.payment_status_confirmed_by::text;
    end if;
    if inv.payment_reference_confirmed_by is not null then
        return next inv.payment_reference_confirmed_by::text;
    end if;
    if inv.pay_from_bank_account_id_confirmed_by is not null then
        return next inv.pay_from_bank_account_id_confirmed_by::text;
    end if;
    if inv.paid_date_confirmed_by is not null then
        return next inv.paid_date_confirmed_by::text;
    end if;
    if inv.credit_memo_confirmed_by is not null then
        return next inv.credit_memo_confirmed_by::text;
    end if;
    if inv.credit_memo_for_invoice_document_id_confirmed_by is not null then
        return next inv.credit_memo_for_invoice_document_id_confirmed_by::text;
    end if;
    if inv.partially_paid_confirmed_by is not null then
        return next inv.partially_paid_confirmed_by::text;
    end if;
    if inv.delivery_note_numbers_confirmed_by is not null then
        return next inv.delivery_note_numbers_confirmed_by::text;
    end if;
    if inv.open_items_number_confirmed_by is not null then
        return next inv.open_items_number_confirmed_by::text;
    end if;
    if inv.ger_clause_35a_net_confirmed_by is not null then
        return next inv.ger_clause_35a_net_confirmed_by::text;
    end if;
    if inv.ger_clause_35a_total_confirmed_by is not null then
        return next inv.ger_clause_35a_total_confirmed_by::text;
    end if;
    if inv.ger_clause_35a_kind_confirmed_by is not null then
        return next inv.ger_clause_35a_kind_confirmed_by::text;
    end if;

    return;
end
$$;

----

create function public.invoice_has_xml_source(
    invoice public.invoice
) returns boolean
language sql immutable strict as $$
    select exists (
        select 1
        from public.invoice_values_confirmed_by(invoice) as confirmed_by
        where confirmed_by::text = any(enum_range(null::public.invoice_xml_source)::text[])
    )
$$;
