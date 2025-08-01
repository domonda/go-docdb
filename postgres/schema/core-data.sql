BEGIN;

\ir data_vat.sql

\echo
\echo '=== core-data.sql ==='
\echo

-- "Libraconsult Steuerberatung GmbH" is the core accounting company used by "DOMONDA GmbH"
INSERT INTO public.company (id, name, brand_name, legal_form, founded, dissolved, updated_at, created_at, source, alternative_names) VALUES
    ('c1fd6da0-e1e5-4607-bc92-885339a37649', 'Libraconsult Steuerberatung GmbH', 'Libraconsult', 'GMBH', NULL, NULL, '2019-01-11 11:35:04.933163', '2017-09-14 17:31:44.238028', 'merged:26bf6082-92e9-49f4-b30c-8336ee9d0241 (GET_OR_CREATE_WITH_NAME)', '{Libraconsult,"libraconsult e.U."}');
WITH client_company AS (
    INSERT INTO public.client_company (company_id, accounting_company_client_company_id, import_members, processing, vat_declaration, email_alias) VALUES
        ('c1fd6da0-e1e5-4607-bc92-885339a37649', 'c1fd6da0-e1e5-4607-bc92-885339a37649', '{}', 'MONTHLY_PROCESSING', 'MONTHLY_VAT_DECLARATION', 'libraconsult')
    RETURNING company_id
)
INSERT INTO public.accounting_company (client_company_id, is_tax_adviser, active) VALUES
    ((SELECT company_id FROM client_company), true, true);
INSERT INTO private.client_company_status (client_company_id, status) VALUES
    ((SELECT company_id FROM client_company), 'ACTIVE');

-- "DOMONDA GmbH" is the core company used by SYSTEM users which are inserted before "domonda-cli users restoreAll"
INSERT INTO public.company (id, name, brand_name, legal_form) VALUES
    ('7acda277-f07c-4975-bd12-d23deace6a9a', 'DOMONDA GmbH', 'domonda', 'GMBH');
INSERT INTO public.client_company (company_id, accounting_company_client_company_id, import_members, processing, vat_declaration, email_alias) VALUES
    ('7acda277-f07c-4975-bd12-d23deace6a9a', 'c1fd6da0-e1e5-4607-bc92-885339a37649', '{}', 'MONTHLY_PROCESSING', 'MONTHLY_VAT_DECLARATION', 'domonda');
INSERT INTO private.client_company_status (client_company_id, status) VALUES
    ('7acda277-f07c-4975-bd12-d23deace6a9a', 'ACTIVE');
-- DOMONDA GmbH is also an accounting company, but not a tax advisor
INSERT INTO public.accounting_company (client_company_id, is_tax_adviser, active) VALUES
    ('7acda277-f07c-4975-bd12-d23deace6a9a', false, true);

-- document type email aliases is used for mapping import emails to correct document category
INSERT INTO public.document_type_email_alias (type, german_alias, english_alias) VALUES
    ('INCOMING_INVOICE', 'er', 'ii'),
    ('OUTGOING_INVOICE', 'ar', 'oi'),
    ('INCOMING_DUNNING_LETTER', 'emahn', 'idun'),
    ('OUTGOING_DUNNING_LETTER', 'mahn', 'dun'),
    ('INCOMING_DELIVERY_NOTE', 'ls', 'del'),
    ('OUTGOING_DELIVERY_NOTE', 'als', 'odel'),
    ('BANK_STATEMENT', 'bk', 'bk'),
    ('CREDITCARD_STATEMENT', 'kk', 'cc'),
    ('FACTORING_STATEMENT', 'factor', 'factor'),
    ('DMS_DOCUMENT', 'dms', 'dms'),
    ('OTHER_DOCUMENT', 'dokument', 'document');

-- booking type email aliases is used for mapping import emails to correct document category
INSERT INTO public.booking_type_email_alias (type, german_alias, english_alias) VALUES
	('CASH_BOOK', 'ka', 'cash'),
    ('CLEARING_ACCOUNT', 'vk', 'ca');

-- SYSTEM users (omitted from the "domonda-cli users dumpAll")
\ir system_users.sql

-- Insert locations after system users because created_by references system user 08a34dc4-6e9a-4d61-b395-d123005e65d3 as default value
INSERT INTO public.company_location (id, company_id, main, street, city, zip, country, phone, email, website, registration_no, tax_id_no, vat_id_no, updated_at, created_at) VALUES
    ('2992d257-e748-43bf-bee7-1e64b23949a3', 'c1fd6da0-e1e5-4607-bc92-885339a37649', true, 'Mariahilfer Straße 36', 'Wien', '1070', 'AT', '+43676841680210', 'spiegel@libraconsult.at', NULL, '435960v', NULL, 'ATU72880778', '2019-01-11 11:35:04.933163', '2017-09-14 17:31:44.238028');
INSERT INTO public.company_location (id, company_id, main, vat_id_no, tax_id_no, registration_no, email, website, street, city, zip, country) VALUES
    ('d8f1f845-f3f1-4232-80be-8fb853e32435', '7acda277-f07c-4975-bd12-d23deace6a9a', true, 'ATU72354846', '09 288/4626', '473473i', 'office@domonda.com', 'https://domonda.com/', 'Haeckelstraße 10/1', 'Wien', '1230', 'AT');

-- Default client_company_user roles
INSERT INTO control.client_company_user_role (
    name,
    -- company
    update_company,
    -- client_companies
    view_client_companies,
    add_client_companies,
    update_client_companies,
    delete_client_companies,
    -- document_categories
    view_document_categories,
    add_document_categories,
    update_document_categories,
    delete_document_categories,
    -- users
    view_users,
    add_users,
    update_users,
    delete_users,
    -- documents (applies to invoices, delivery_notes)
    view_documents,
    add_documents,
    update_documents,
    delete_documents,
    -- money_accounts
    view_money_accounts,
    add_money_accounts,
    update_money_accounts,
    delete_money_accounts,
    -- money_transactions
    view_money_transactions
) VALUES (
        'DEFAULT',
        false,       -- update_company
        false,       -- view_client_companies
        false,       -- add_client_companies
        false,       -- update_client_companies
        false,       -- delete_client_companies
        false,       -- view_document_categories
        false,       -- add_document_categories
        false,       -- update_document_categories
        false,       -- delete_document_categories
        false,       -- view_users
        false,       -- add_users
        false,       -- update_users
        false,       -- delete_users
        false,       -- view_documents
        false,       -- add_documents
        false,       -- update_documents
        false,       -- delete_documents
        false,       -- view_money_accounts
        false,       -- add_money_accounts
        false,       -- update_money_accounts
        false,       -- delete_money_accounts
        false        -- view_money_transactions
    ), (
        'ADMIN',
        true,       -- update_company
        true,       -- view_client_companies
        true,       -- add_client_companies
        true,       -- update_client_companies
        true,       -- delete_client_companies
        true,       -- view_document_categories
        true,       -- add_document_categories
        true,       -- update_document_categories
        true,       -- delete_document_categories
        true,       -- view_users
        true,       -- add_users
        true,       -- update_users
        true,       -- delete_users
        true,       -- view_documents
        true,       -- add_documents
        true,       -- update_documents
        true,       -- delete_documents
        true,       -- view_money_accounts
        true,       -- add_money_accounts
        true,       -- update_money_accounts
        true,       -- delete_money_accounts
        true        -- view_money_transactions
    ), (
        'ACCOUNTANT',
        true,       -- update_company
        true,       -- view_client_companies
        true,       -- add_client_companies
        true,       -- update_client_companies
        true,       -- delete_client_companies
        true,       -- view_document_categories
        true,       -- add_document_categories
        true,       -- update_document_categories
        true,       -- delete_document_categories
        true,       -- view_users
        true,       -- add_users
        true,       -- update_users
        true,       -- delete_users
        true,       -- view_documents
        true,       -- add_documents
        true,       -- update_documents
        true,       -- delete_documents
        true,       -- view_money_accounts
        true,       -- add_money_accounts
        true,       -- update_money_accounts
        true,       -- delete_money_accounts
        true        -- view_money_transactions
    ), (
        'CLIENT',
        false,       -- update_company
        false,       -- view_client_companies
        false,       -- add_client_companies
        false,       -- update_client_companies
        false,       -- delete_client_companies
        true,        -- view_document_categories
        false,       -- add_document_categories
        false,       -- update_document_categories
        false,       -- delete_document_categories
        false,       -- view_users
        false,       -- add_users
        false,       -- update_users
        false,       -- delete_users
        true,        -- view_documents
        true,        -- add_documents
        true,        -- update_documents
        true,        -- delete_documents
        true,        -- view_money_accounts
        true,        -- add_money_accounts
        true,        -- update_money_accounts
        true,        -- delete_money_accounts
        true         -- view_money_transactions
    ), (
        'DOCUMENTS_ONLY',
        false,       -- update_company
        false,       -- view_client_companies
        false,       -- add_client_companies
        false,       -- update_client_companies
        false,       -- delete_client_companies
        false,       -- view_document_categories
        false,       -- add_document_categories
        false,       -- update_document_categories
        false,       -- delete_document_categories
        false,       -- view_users
        false,       -- add_users
        false,       -- update_users
        false,       -- delete_users
        true,        -- view_documents
        true,        -- add_documents
        true,        -- update_documents
        false,       -- delete_documents
        false,       -- view_money_accounts
        false,       -- add_money_accounts
        false,       -- update_money_accounts
        false,       -- delete_money_accounts
        false        -- view_money_transactions
    ), (
        'COLLABORATION_ONLY',
        false,       -- update_company
        false,       -- view_client_companies
        false,       -- add_client_companies
        false,       -- update_client_companies
        false,       -- delete_client_companies
        false,       -- view_document_categories
        false,       -- add_document_categories
        false,       -- update_document_categories
        false,       -- delete_document_categories
        false,       -- view_users
        false,       -- add_users
        false,       -- update_users
        false,       -- delete_users
        true,        -- view_documents
        false,       -- add_documents
        true,        -- update_documents (should be able to change workflow steps)
        false,       -- delete_documents
        false,       -- view_money_accounts
        false,       -- add_money_accounts
        false,       -- update_money_accounts
        false,       -- delete_money_accounts
        false        -- view_money_transactions
    ), (
        'VERIFIER',
        false,       -- update_company
        false,       -- view_client_companies
        false,       -- add_client_companies
        false,       -- update_client_companies
        false,       -- delete_client_companies
        false,       -- view_document_categories
        false,       -- add_document_categories
        false,       -- update_document_categories
        false,       -- delete_document_categories
        false,       -- view_users
        false,       -- add_users
        false,       -- update_users
        false,       -- delete_users
        true,        -- view_documents
        true,        -- add_documents
        true,        -- update_documents
        false,       -- delete_documents
        false,       -- view_money_accounts
        false,       -- add_money_accounts
        false,       -- update_money_accounts
        false,       -- delete_money_accounts
        false        -- view_money_transactions
    );


-- Special EXTERNAL client company used for external work group sharing users
insert into public.company (id, name)
    values ('391c0362-5fee-43f5-9a44-27e88130b6a6', 'EXTERNAL');
insert into public.company_location (id, company_id, main)
    values ('ceac4151-18d8-419e-943b-f795664d05eb', '391c0362-5fee-43f5-9a44-27e88130b6a6', true);
insert into public.client_company (company_id, accounting_company_client_company_id, email_alias)
    values ('391c0362-5fee-43f5-9a44-27e88130b6a6', 'c1fd6da0-e1e5-4607-bc92-885339a37649', 'external');

-- Work Group default rights
\ir work/rights_defaults.sql

COMMIT;
