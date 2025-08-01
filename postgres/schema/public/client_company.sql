create type public.vat_declaration_frequency as enum (
	'MONTHLY_VAT_DECLARATION',
	'QUARTERLY_VAT_DECLARATION',
	'YEARLY_VAT_DECLARATION',
	'NO_VAT_DECLARATION'
);

comment on type public.vat_declaration_frequency is 'When the company declares its VAT';

----

create type public.processing_frequency as enum (
	'NO_PROCESSING',    -- no accountant
	'DAILY_PROCESSING', -- default

	'MONDAY_PROCESSING',    -- deprecated
	'TUESDAY_PROCESSING',   -- deprecated
	'WEDNESDAY_PROCESSING', -- deprecated
	'THURSDAY_PROCESSING',  -- deprecated
	'FRIDAY_PROCESSING',    -- deprecated
	'MONTHLY_PROCESSING',   -- deprecated
	'QUARTERLY_PROCESSING', -- deprecated
	'YEARLY_PROCESSING'     -- deprecated
);

comment on type public.processing_frequency is 'When the company documents are processed';

----

create type public.accounting_system as enum (
	'CUSTOM_BOOKED', -- Used to mark invoices as booked for an undefined accounting system
	'BMD',
	'DATEV',
	'DVO', -- Based on BMD
	'RZL',
	'ADDISON',  -- Based on DATEV with a different export empty value placholder
	'AGENDA',   -- Based on DATEV CSV
	'LEXWARE',
	'CONTHAUS', -- Based on BMD
	'WINCASA',  -- Based on DATEV CSV
	'DOMUS',
	'SIDOMO',
	'FLUKS',
	'REAL_DATA',
	'KARTHAGO'
);

comment on type public.accounting_system is 'The accounting system this client wishes to use.';

----

create function public.vat_accounting_system(
  sys public.accounting_system
) returns public.accounting_system
language sql immutable strict as
$$
	select case sys
		when 'ADDISON'  then 'DATEV'::public.accounting_system
		when 'LEXWARE'  then 'DATEV'::public.accounting_system
		when 'CONTHAUS' then 'BMD'::public.accounting_system
		when 'WINCASA'  then 'DATEV'::public.accounting_system
		else sys
	end
$$;

comment on function public.vat_accounting_system is 'Accounting system used for VAT codes';

----

create type public.extraction_service as enum (
	'NONE',
	'SIMPLE_INTERNAL',
	'BLUDELTA',
	'SIMPLE_INTERNAL_AND_BLUDELTA',
	'BLUDELTA2',
	'SIMPLE_INTERNAL_AND_BLUDELTA2',
	'DOCVIBE',
	'SIMPLE_INTERNAL_AND_DOCVIBE'
);

comment on type public.extraction_service is 'Identifies a document extraction service';

create function public.default_extraction_service() returns public.extraction_service
language sql immutable parallel safe as
$$
	select 'SIMPLE_INTERNAL_AND_BLUDELTA'::public.extraction_service
$$;

----

create type public.chart_of_accounts as enum (
	'SKR03',
	'SKR04',
	'SKR07'
);

comment on type public.chart_of_accounts is 'The chart of accounts used for the general ledger';

----

create type public.branding as enum (
	'IDWELL',
	'KIRA',
	'HCSM'
);

comment on type public.branding is 'The branding used for this client.';

----

create function public.default_payment_reminder_message(
	"language" public.language_code
) returns non_empty_text as $$
	select case default_payment_reminder_message.language
		when 'de' then
			'Sehr geehrter Geschäftspartner,' || E'\n\n' || E'nach Durchsicht unserer Buchhaltung mussten wir leider feststellen, dass bis dato keine Zahlung für die beigefügte Rechnung eingelangt ist. Wir bitte Sie um prompte Erledigung.' || E'\n\n' || E'Vielen Dank'
		else
			'Dear business partner,' || E'\n\n' || E'After reviewing our accounting, we unfortunately found that no payment has been received for the attached invoice to date. We kindly ask that you deal with this promptly.' || E'\n\n' || E'Thank you'
	end
$$ language sql immutable strict;

----

create table public.client_company (
	company_id               uuid primary key references public.company(id),
	"language"               public.language_code not null default 'de',
	branding                 public.branding,
	email_alias              text not null unique check(email_alias ~ '^[a-z0-9\-_.]+$'),
	billed_client_company_id uuid
		references public.client_company(company_id) on delete set null,

	import_members text[] not null default '{}',
	-- all money transactions that have these keywords (case-insensitive) in the purpose/reference
	-- will be filtered out/omitted during import and will never enter the database
	filter_transactions_keywords trimmed_text[] not null default '{}',
	custom_extraction_service    public.extraction_service, -- null means no customization, use default

	accounting_currency                  public.currency_code not null default 'EUR',
	accounting_email                     public.email_addr, -- the email to receive accounting related messages
	accounting_company_client_company_id uuid not null
		default '7acda277-f07c-4975-bd12-d23deace6a9a' -- DOMONDA GmbH
		references public.accounting_company(client_company_id) on delete set default,
	unique(company_id, accounting_company_client_company_id),
	accounting_system           public.accounting_system,
	accounting_system_client_no text check(length(trim(accounting_system_client_no)) > 0),
	unique(accounting_system_client_no, accounting_company_client_company_id),
	accounting_export_dest_url        trimmed_text, -- SFTP URL including port and username
	accounting_export_doc_link_prefix trimmed_text, -- filename prefix used to create a document link within an accounting export format

	tax_reclaimable       boolean not null default true,
	vat_declaration       public.vat_declaration_frequency not null default 'MONTHLY_VAT_DECLARATION',
	processing            public.processing_frequency not null default 'DAILY_PROCESSING',
	chart_of_accounts     public.chart_of_accounts,
	gl_number_length      int check(gl_number_length >= 4 and gl_number_length <= 7),            -- default 4
	partner_number_length int check(partner_number_length >= 5 and partner_number_length <= 10), -- default 5

	contract_start_date date,
	contract_note       non_empty_text,
	licensed_documents  int,
	licensed_users      int,
	licensed_banks      int,

	contract_expiry_notification_email public.email_addr, -- the email about other documents contracts reaching their expiry date
	pain008_payment_id                 trimmed_text,
	blacklist_partner_vat_id_nos       text[] not null default '{}',
	notes                              non_empty_text,

	append_audit_trail                    boolean not null default false,
	invoice_cost_centers                  boolean not null default true,
	accounting_item_cost_centers          boolean not null default true,
	invoice_cost_units                    boolean not null default false,
	accounting_item_cost_units            boolean not null default false,
	abandoned_documents_warning           boolean not null default false,
	create_partner                        boolean not null default true,
	create_partner_account                boolean not null default true,
	bmd_bankinfo                          boolean not null default false,
	restrict_booking_export               boolean not null default false,
	disable_incomplete_export             boolean not null default false,
	disable_review_workflow_manage        boolean not null default false,
	disable_unverified_iban_check         boolean not null default false,
	invoice_internal_number_count_up_mode boolean not null default false,
	invoice_internal_number_min           bigint,
	disable_invoice_internal_number_edit  boolean not null default false,
	restrict_document_delete              boolean not null default false,
	assign_protected_document_category    boolean not null default false,
	ibans                                 public.bank_iban[] not null default '{}',
	skip_matching_check_ids               uuid[] not null default '{}',
	custom_payment_reminder_message       non_empty_text,
	factor_bank_customer_number           bigint,

	updated_at updated_time not null,
	created_at created_time not null
);

create index client_company_billed_client_company_id_idx on public.client_company (billed_client_company_id);
create index client_company_accounting_company_client_company_id_idx on public.client_company (accounting_company_client_company_id);
create index client_company_accounting_system_idx on public.client_company (accounting_system);

grant select on table public.client_company to domonda_user;
grant select on table public.client_company to domonda_wg_user; -- TODO: just select I guess?

-- add missing reference to the accounting company
alter table public.accounting_company
    add constraint accounting_company_client_company_id_fkey
        foreign key (client_company_id)
        references public.client_company(company_id)
        on delete cascade
        deferrable;

----

create function public.client_company_has_accounting_system(
	client_company public.client_company
) returns boolean as $$
	select client_company.accounting_system is not null
$$ language sql immutable strict;

comment on function public.client_company_has_accounting_system is '@notNull';

create function public.has_client_company_an_accounting_system(
	client_company_id uuid
) returns boolean as $$
	select public.client_company_has_accounting_system(client_company)
	from public.client_company where company_id = client_company_id
$$ language sql stable strict;

comment on function public.has_client_company_an_accounting_system is '@notNull';

----

create function public.update_client_company_email_alias(
	client_company_id uuid,
	email_alias public.email_alias
) returns public.client_company as $$
	update public.client_company
	set email_alias=update_client_company_email_alias.email_alias, updated_at=now()
	where company_id = update_client_company_email_alias.client_company_id
	returning *
$$ language sql volatile strict security definer;

----

create function public.update_safe_client_company(
	company_id                         uuid,
	"language"                         public.language_code = null,
	accounting_email                   public.email_addr = null,
	contract_expiry_notification_email public.email_addr = null,
	pain008_payment_id                 trimmed_text = null,
	blacklist_partner_vat_id_nos       text[] = '{}',
	notes                              non_empty_text = null
) returns public.client_company as $$
	update public.client_company set
		"language"=update_safe_client_company.language,
		accounting_email=update_safe_client_company.accounting_email,
		contract_expiry_notification_email=update_safe_client_company.contract_expiry_notification_email,
		pain008_payment_id=update_safe_client_company.pain008_payment_id,
		blacklist_partner_vat_id_nos=update_safe_client_company.blacklist_partner_vat_id_nos,
		notes=update_safe_client_company.notes,
		updated_at=now()
	where client_company.company_id = update_safe_client_company.company_id
	returning *
$$ language sql volatile security definer;

----

create function public.update_advanced_client_company(
	company_id                            uuid,
	append_audit_trail                    boolean,
	invoice_cost_centers                  boolean,
	abandoned_documents_warning           boolean,
	create_partner                        boolean,
	create_partner_account                boolean,
	bmd_bankinfo                          boolean,
	restrict_booking_export               boolean,
	disable_incomplete_export             boolean,
	disable_review_workflow_manage        boolean,
	disable_unverified_iban_check         boolean,
	invoice_internal_number_count_up_mode boolean,
	disable_invoice_internal_number_edit  boolean,
	restrict_document_delete              boolean,
	assign_protected_document_category    boolean,
	ibans                                 public.bank_iban[],
	skip_matching_check_ids               uuid[],
	custom_payment_reminder_message       non_empty_text
) returns public.client_company as $$
	update public.client_company set
		append_audit_trail=update_advanced_client_company.append_audit_trail,
		invoice_cost_centers=update_advanced_client_company.invoice_cost_centers,
		abandoned_documents_warning=update_advanced_client_company.abandoned_documents_warning,
		create_partner=update_advanced_client_company.create_partner,
		create_partner_account=update_advanced_client_company.create_partner_account,
		bmd_bankinfo=update_advanced_client_company.bmd_bankinfo,
		restrict_booking_export=update_advanced_client_company.restrict_booking_export,
		disable_incomplete_export=update_advanced_client_company.disable_incomplete_export,
		disable_review_workflow_manage=update_advanced_client_company.disable_review_workflow_manage,
		disable_unverified_iban_check=update_advanced_client_company.disable_unverified_iban_check,
		invoice_internal_number_count_up_mode=update_advanced_client_company.invoice_internal_number_count_up_mode,
		disable_invoice_internal_number_edit=update_advanced_client_company.disable_invoice_internal_number_edit,
		restrict_document_delete=update_advanced_client_company.restrict_document_delete,
		assign_protected_document_category=update_advanced_client_company.assign_protected_document_category,
		ibans=update_advanced_client_company.ibans,
		skip_matching_check_ids=update_advanced_client_company.skip_matching_check_ids,
		custom_payment_reminder_message=update_advanced_client_company.custom_payment_reminder_message,
		updated_at=now()
	where client_company.company_id = update_advanced_client_company.company_id
	returning *
$$ language sql volatile security definer;

----

create function public.client_company_extraction_service(
	client_company public.client_company
) returns public.extraction_service
language sql immutable strict as
$$
	select coalesce(
		client_company.custom_extraction_service,
		default_extraction_service()
	)
$$;

comment on function public.client_company_extraction_service is '@notNull';

----

create function public.client_company_payment_reminder_message(
	client_company public.client_company
) returns non_empty_text as $$
	select coalesce(
		client_company.custom_payment_reminder_message,
		public.default_payment_reminder_message(client_company.language)
	)
$$ language sql immutable strict;

comment on function public.client_company_payment_reminder_message is '@notNull';
