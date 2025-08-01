create type object.prop_type as enum (
    'TEXT',                  -- public.trimmed_text
    'TEXT_ARRAY',            -- public.trimmed_text
    'TEXT_OPTION',           -- text
    'TEXT_OPTION_ARRAY',     -- text
    'ACCOUNT_NO',            -- public.account_no
    'ACCOUNT_NO_ARRAY',      -- public.account_no
    'NUMBER',                -- float8
    'NUMBER_ARRAY',          -- float8
    'INTEGER',               -- bigint
    'INTEGER_ARRAY',         -- bigint
    'BOOLEAN',               -- boolean
    'DATE',                  -- date
    'DATE_ARRAY',            -- date
    'DATE_TIME',             -- timestamptz
    'DATE_TIME_ARRAY',       -- timestamptz
    'IBAN',                  -- public.bank_iban
    'IBAN_ARRAY',            -- public.bank_iban
    'BIC',                   -- public.bank_bic
    'BIC_ARRAY',             -- public.bank_bic
    'VAT_ID',                -- public.vat_id
    'VAT_ID_ARRAY',          -- public.vat_id
    'COUNTRY',               -- public.country_code
    'COUNTRY_ARRAY',         -- public.country_code
    'CURRENCY',              -- public.currency_code
    'CURRENCY_ARRAY',        -- public.currency_code
    'CURRENCY_AMOUNT',       -- public.currency_code + float8
    'CURRENCY_AMOUNT_ARRAY', -- public.currency_code + float8
    'EMAIL_ADDRESS',         -- public.email_addr
    'EMAIL_ADDRESS_ARRAY',   -- public.email_addr
    'USER',                  -- public.user(id)
    'USER_ARRAY',            -- public.user(id)
    'BANK_ACCOUNT',
    'BANK_ACCOUNT_ARRAY'

    -- TODO types:
    -- 'DOCUMENT',          -- public.document(id)
    -- 'MONEY_TRANSACTION', -- public.public.money_transaction(id)
    -- 'CLIENT_COMPANY',    -- public.client_company(id)
    -- 'PARTNER_COMPANY',   -- public.partner_company(id)
    -- 'PARTNER_ACCOUNT',   -- public.partner_account(id)
    -- 'COST_CENTER',       -- public.client_company_cost_center(id)
    -- 'COST_UNIT',         -- public.client_company_cost_unit(id)
    -- 'VAT_TYPE'           -- public.value_added_tax(id)
);

create function object.prop_type_is_array(t object.prop_type) returns boolean
language sql immutable as $$
    select right(t::text, 6) = '_ARRAY';
$$;

create function object.prop_type_has_options(t object.prop_type) returns boolean
language sql immutable as $$
    select t in ('TEXT_OPTION', 'TEXT_OPTION_ARRAY');
$$;

create function object.prop_type_table(t object.prop_type) returns text
language sql immutable as $$
    select 'object.' || lower(replace(t::text, '_ARRAY', '')) || '_prop';
$$;