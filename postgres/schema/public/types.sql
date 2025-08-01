CREATE DOMAIN public.created_time timestamptz DEFAULT now();
COMMENT ON DOMAIN public.created_time IS 'Timestamp for creation of data entries';

----

CREATE DOMAIN public.updated_time timestamptz DEFAULT now();
COMMENT ON DOMAIN public.updated_time IS 'Timestamp for update of data entries';

----

create domain public.email_addr text
    constraint email_address_format check (value ~ '^.+@.+\.(.+\.)?.+$')
    constraint lowercase_email check (value = lower(value));
comment on domain public.email_addr is 'Email address with simple plausability and lower case check';

----

CREATE DOMAIN public.email_alias text CHECK (VALUE ~ '^[a-z0-9\+\-_.]+$');
COMMENT ON DOMAIN public.email_alias IS 'An alias for a document type that can be used in email addresses';

----

CREATE DOMAIN public.country_code char(2) CHECK ( (length(VALUE) = 2) AND (VALUE <> '  ') AND (VALUE = upper(VALUE)) );
COMMENT ON DOMAIN public.country_code IS 'Two character upper case country code';

----

CREATE DOMAIN public.language_code char(2) CHECK ( (length(VALUE) = 2) AND (VALUE <> '  ') AND (VALUE = lower(VALUE)) );
COMMENT ON DOMAIN public.language_code IS 'Two character lower case language code';

----

CREATE DOMAIN public.currency_code char(3) CHECK ( (length(VALUE) = 3) AND (VALUE <> '   ') AND (VALUE = upper(VALUE)) );
COMMENT ON DOMAIN currency_code IS 'ISO 4217 Currency Code';

----

create type public.currency_amount as (
    currency public.currency_code,
    amount   float8
);

create function public.currency_amount_is_not_null(ca public.currency_amount) returns boolean
language sql immutable as
$$
    select ca is not null and ca.amount is not null and ca.currency is not null
$$;

create function public.currency_amount_text(ca public.currency_amount) returns text
language sql immutable strict as
$$
    select ca.currency::text||' '||to_char(ca.amount, '999999999999.99')
$$;

create function public.currency_amount_text_de(ca public.currency_amount) returns text
language sql immutable strict as
$$
    select ca.currency::text||' '||replace(to_char(ca.amount, '999999999999.99'), '.', ',')
$$;

----

CREATE DOMAIN public.bank_iban text CHECK (VALUE ~ '^([A-Z]{2})(\d{2})([A-Z\d]{8,30})$');
COMMENT ON DOMAIN public.bank_iban IS 'International Bank Account Number';

----

CREATE DOMAIN public.bank_bic text CHECK (VALUE ~ '^([A-Z]{4})([A-Z]{2})([A-Z0-9]{2})([A-Z0-9]{3})?$');
-- CREATE DOMAIN bank_bic text CHECK (length(VALUE) > 0);
COMMENT ON DOMAIN public.bank_bic IS 'SWIFT Business Identifier Code';

----

CREATE DOMAIN public.credit_card_no text CHECK (VALUE ~ '^\d{16}$');
COMMENT ON DOMAIN public.credit_card_no IS '16 digit credit card number without spaces';

----

-- CREATE DOMAIN public.payment_card_number text CHECK (VALUE ~ '^$');
-- COMMENT ON DOMAIN public.payment_card_number IS 'Payment card number or primary account number (PAN) used for credit cards';

----

create collation "numeric" (provider = icu, locale = 'en-u-kn-true');

----

create domain public.non_empty_text text check(length(trim(value)) > 0);
comment on domain public.non_empty_text is 'Text type which must have at least one non-space character.';

create domain public.trimmed_text text check(length(value) > 0 and length(value) = length(trim(value)));
comment on domain public.trimmed_text is 'Non empty text without leading or trailing whitespace.';

create domain public.account_no text
    -- collate "numeric" -- TODO use collation by default, but needs to change the type in all tables
    check(value ~ '^[0-9A-Za-z][0-9A-Za-z_\-\/:.;,]*$');
comment on domain public.account_no is 'Non empty account number consisting only of digits and basic alphabet characters';


----

CREATE TYPE public.legal_form AS ENUM (
    'GMBH',            -- GmbH
    'GMBH_CO_KG',      -- GmbH & Co. KG
    'KG',              -- Kommanditgesellschaft
    'AG',              -- Aktiengesellschaft
    'OG',              -- Offene Gesellschaft
    'EV',              -- Eingetragener Verein (e.V.)
    'EU',              -- Eingetragenes Unternehmen
	'FLEXCO',          -- Austrian FlexCo or FlexKapG
	'EG',              -- German eingetragene Genossenschaft (e.G.)
    'SOLE_PROPRIETOR', -- Einzelunternehmen
    'LTD',             -- Limited
    'LLC',             -- Limited Liability Company
    'INC',             -- Incorporated
    'CLUB',            -- Verein
    'SRO',             -- Společnost s ručením omezeným (s.r.o) - tschechische GmbH
    'AS',              -- Akciová společnost (a.s.) - tschechische AG
    'KFT',             -- Korlátolt felelősségű társaság (Kft.) - ungarische GmbH
    'SPZOO'            -- Spółka z ograniczoną odpowiedzialnością (Sp. z o.o.) - polnische GmbH
);

COMMENT ON TYPE public.legal_form IS 'Legal form of a company';

----

-- CREATE TYPE public.ocr_pos AS (
--     page       int,
-- 	x0         float8,
-- 	y0         float8,
-- 	x1         float8,
-- 	y1         float8,
--     angle      float8,
--     baseline   float8,
--     -- font_size  float8,
--     confidence float8
-- );

----

create function private.is_vat_id(
    value text
) returns boolean as $$
declare
    min_len int = 4;
    max_len int = 14 + 2; -- allow 2 spaces
    country_code_regex jsonb = $jsonb${
        "AT": "^AT\\s??U\\s??\\d{8}$",
        "BE": "^BE\\s??\\d{10}$",
        "BG": "^BG\\s??\\d{9,10}$",
        "CH": "^CHE\\s??-?(?:\\d{9}|(?:\\d{3}\\.\\d{3}\\.\\d{3}))$",
        "CY": "^CY\\s??\\d{8}[A-Z]$",
        "CZ": "^CZ\\s??\\d{8,10}$",
        "DE": "^DE\\s??[1-9]\\d{8}$",
        "DK": "^DK\\s??\\d{8}$",
        "EE": "^EE\\s??\\d{9}$",
        "EL": "^EL\\s??\\d{9}$",
        "ES": "^ES\\s??[0-9A-Z]\\s??\\d{7}[0-9A-Z]$",
        "FI": "^FI\\s??\\d{8}$",
        "FR": "^FR\\s??[0-9A-Z][0-9A-Z]\\s??\\d{9}$",
        "GB": "^GB\\s??(?:\\d{9})|(?:\\d{12})|(?:GD\\d{3})|(?:HA\\d{3})$",
        "HR": "^HR\\s??\\d{11}$",
        "HU": "^HU\\s??\\d{8,9}$",
        "IE": "^IE\\s??(?:\\d[0-9A-Z]\\d{5}[A-Z])|(?:\\d{7}[A-W][A-I])$",
        "IT": "^IT\\s??\\d{11}$",
        "LT": "^LT\\s??(?:\\d{9}|\\d{12})$",
        "LU": "^LU\\s??\\d{8}$",
        "LV": "^LV\\s??\\d{11}$",
        "MT": "^MT\\s??\\d{8}$",
        "NL": "^NL\\s??\\d{9}B\\d{2}$",
        "NO": "^NO\\s??\\d{9}\\s??(?:MVA)?$",
        "PL": "^PL\\s??\\d{10}$",
        "PT": "^PT\\s??\\d{9}$",
        "RO": "^RO\\s??\\d{2,10}$",
        "SE": "^SE\\s??\\d{12}$",
        "SI": "^SI\\s??\\d{8}$",
        "SK": "^SK\\s??\\d{10}$",
        "EU": "^EU\\s??\\d{9}$"
    }$jsonb$;
    country_code text;
begin
    if length(value) < min_len then
        return false;
    end if;
    if length(value) > max_len then
        return false;
    end if;

    value := upper(value);
    country_code := left(value, 2);
    if not (country_code_regex ? country_code) then
        -- country code does not exist in the regex map
        return false;
    end if;

    if not (value ~ (country_code_regex->>country_code)) then
        -- value does not match the country code regex
        return false;
    end if;

    return true;
end
$$ language plpgsql immutable strict;

create domain vat_id text check (private.is_vat_id(value));
comment on domain vat_id is 'EU VAT Identifier Code';

----

create function private.sum_func(
  double precision, pg_catalog.anyelement, double precision
) returns double precision as $$
select case when $3 is not null then coalesce($1, 0) + $3 else $1 end
$$ language sql immutable;

-- distinct sum, use like this: `select private.dist_sum(distinct id, balance) from public.money_account`
create aggregate private.dist_sum (pg_catalog."any", double precision)
(
  SFUNC = private.sum_func,
  STYPE = float8
);

----

create function private.business_hours_between("from" timestamptz, "to" timestamptz)
returns int as $$
  select count(*)::int
    from generate_series("from", "to", interval '1 hour') as d
  where extract (isodow from d) between 1 and 5
  and extract (hour from d) between 9 and 16
  -- working hours 8 to 16, but we start with 9 to skip the first hour when summing multiple days
$$ language sql immutable strict;
