create type public.other_document_type as enum (
  'CONTRACTS_ANNEXES', -- Contracts & Annexes / Verträge und Zusatzdokumente
  'INSURANCE_POLICY', -- Insurance policy / Versicherungspolice
  'ANNUAL_FINANCIAL_STATEMENT', -- Annual Financial Statement / Jahresabschluss
  'OFFER', -- Offer / Angebot
  'ORDER', -- Order / Bestellung
  'TAX_STATEMENT', -- Tax Statement / Steuerbescheid
  'BANK_STATEMENT', -- Bank Statement / Bank Kontoauszug
  'CREDITCARD_STATEMENT', -- Creditcard Statement / Kreditkartenabrechnung
  'STATEMENT_FOR_BILLING', -- Statement for Billing / Prüfdokument für Abrechnung
  'SHIPPING_NOTE', -- Shipping note / Lieferschein
  'DUNNING_LETTER', -- Dunning letter / Mahnung
  'NON_COMPLIANT_INVOICES', -- Non compliant Invoices / Nicht-kontierbare Rechnungen
  'EXPENSE_ACCOUNTS', -- Expense accounts / Spesenaufstellungen
  'PAYROLL_DOCUMENTS', -- Payroll documents / Lohnlisten und Zusatzdokumente
  'CASH_BOOK', -- Cash book / Kassabuch
  'GRANTS', -- Grants / Förderungen,
  'REPORTS', -- Reports / Berichte
  'OTHER' -- Other / Sonstiges
);

create type public.other_document_contract_type as enum (
    'ACQUISITION_AGREEMENTS',
    'ADVICE_SUPPORT_AGREEMENTS',
    'AGENCY_AGREEMENTS',
    'CONTRACTS_OF_CARRIAGE',
    'CREDIT_LOAN_AGREEMENTS',
    'FINANCIAL_STATEMENTS',
    'GUARANTEES_SECURITY DEPOSITS',
    'INSURANCE_CONTRACTS',
    'LIABILITY_AGREEMENTS',
    'LICENSE_AGREEMENTS',
    'MAINTENANCE_CONTRACTS',
    'NOTICES',
    'RENTAL_LEASE_AGREEMENTS',
    'SERVICE_CONTRACTS',
    'SUPPLY_PURCHASE_AGREEMENTS',
    'TEST_REPORTS',
    'TRADE_LICENCES',
    'TRANSCRIPTS_NOTICES',
    'VEHICLE_DOCUMENTS'
);

create table public.other_document (
  document_id uuid primary key references public.document(id) on delete cascade,

  "type"          public.other_document_type not null,
  type_changed_by uuid not null references public.user(id),
  type_changed_at timestamptz not null,

  partner_company_id            uuid references public.partner_company(id),
  partner_company_id_changed_by uuid references public.user(id),
  partner_company_id_changed_at timestamptz,
  constraint partner_company_id_changed_by_and_at_both_set_or_not check((partner_company_id_changed_by is null) = (partner_company_id_changed_at is null)),

  document_date            date,
  document_date_changed_by uuid references public.user(id),
  document_date_changed_at timestamptz,
  constraint document_date_changed_by_and_at_both_set_or_not check((document_date_changed_by is null) = (document_date_changed_at is null)),

  document_number            non_empty_text,
  document_number_changed_by uuid references public.user(id),
  document_number_changed_at timestamptz,
  constraint document_number_changed_by_and_at_both_set_or_not check((document_number_changed_by is null) = (document_number_changed_at is null)),

  document_details            non_empty_text,
  document_details_changed_by uuid references public.user(id),
  document_details_changed_at timestamptz,
  constraint document_details_changed_by_and_at_both_set_or_not check((document_details_changed_by is null) = (document_details_changed_at is null)),

  resubmission_date            date,
  resubmission_date_changed_by uuid references public.user(id),
  resubmission_date_changed_at timestamptz,
  constraint resubmission_date_changed_by_and_at_both_set_or_not check((resubmission_date_changed_by is null) = (resubmission_date_changed_at is null)),

  expiry_date            date,
  expiry_date_changed_by uuid references public.user(id),
  expiry_date_changed_at timestamptz,
  constraint expiry_date_changed_by_and_at_both_set_or_not check((expiry_date_changed_by is null) = (expiry_date_changed_at is null)),

  contract_type            public.other_document_contract_type,
  contract_type_changed_by uuid references public.user(id),
  contract_type_changed_at timestamptz,
  constraint contract_type_changed_by_and_at_both_set_or_not check((contract_type_changed_by is null) = (contract_type_changed_at is null)),

  contact_user_id            uuid references public.user(id),
  contact_user_id_changed_by uuid references public.user(id),
  contact_user_id_changed_at timestamptz,
  constraint contact_user_id_changed_by_and_at_both_set_or_not check((contact_user_id_changed_by is null) = (contact_user_id_changed_at is null)),

  -- DO NOT FORGET TO ADD NEW FIELDS TO public.document_field

  updated_at updated_time not null,
  created_at created_time not null
);

grant select, update on table public.other_document to domonda_user;
grant select on table public.other_document to domonda_wg_user; -- TODO: add RLS policies for UPDATE

create index other_document_partner_company_id_idx on public.other_document (partner_company_id);
create index other_document_contact_user_id_idx on public.other_document (contact_user_id);

----

create function public.other_document_partner_name(
    other_document public.other_document
) returns text as $$
    select partner_company.derived_name
    from public.partner_company
    where id = other_document.partner_company_id
$$ language sql stable strict;

----

create function private.other_document_last_changed(
    other_document public.other_document
) returns record as $$
declare
    last_at timestamptz;
    last_by uuid;
begin
    -- start with the partner last edit at
    last_at := other_document.type_changed_at;
    last_by := other_document.type_changed_by;

    if last_at is null or last_at < other_document.partner_company_id_changed_at then
        last_at := other_document.partner_company_id_changed_at;
        last_by := other_document.partner_company_id_changed_by;
    end if;

    if last_at is null or last_at < other_document.document_date_changed_at then
        last_at := other_document.document_date_changed_at;
        last_by := other_document.document_date_changed_by;
    end if;

    if last_at is null or last_at < other_document.document_number_changed_at then
        last_at := other_document.document_number_changed_at;
        last_by := other_document.document_number_changed_by;
    end if;

    -- null record is different from null value
    if last_by is null then return null; end if;
    return (last_by, last_at);
end
$$ language plpgsql stable strict;

create function public.other_document_last_changed_by(
    other_document public.other_document
) returns public.user as $$
    select "user".* from private.other_document_last_changed(other_document) as (by uuid, at timestamptz)
        inner join public."user" on "user".id = by
$$ language sql stable strict;
comment on function public.other_document_last_changed_by is 'Last change on _any_ other document field performed by.';

create function public.other_document_last_changed_at(
    other_document public.other_document
) returns timestamptz as $$
    select at from private.other_document_last_changed(other_document) as (by uuid, at timestamptz)
$$ language sql stable strict;
comment on function public.other_document_last_changed_at is 'Last change on _any_ other document field performed at.';
