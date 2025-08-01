CREATE TABLE matching.check (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    name        text UNIQUE NOT NULL CHECK (length(name) >= 3), -- at least 3 characters
    description text,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT SELECT ON matching.check TO domonda_user;

COMMENT ON TABLE matching.check IS '@name matchingCheck';

----

CREATE TYPE matching.transaction_type AS ENUM (
    'CREDIT_CARD',
    'BANK'
);

COMMENT ON TYPE matching.transaction_type IS '@name matchingTransactionType';

CREATE TABLE matching.check_transaction_type (
    check_id uuid PRIMARY KEY REFERENCES matching.check (id) ON DELETE CASCADE,

    transaction_type matching.transaction_type NOT NULL
);

GRANT SELECT ON matching.check_transaction_type TO domonda_user;

COMMENT ON TABLE matching.check_transaction_type IS '@name matchingCheckTransactionType';

----

CREATE TABLE matching.check_totals (
    check_id uuid PRIMARY KEY REFERENCES matching.check (id) ON DELETE CASCADE,

    max_diff          numeric NOT NULL CHECK (max_diff >= 0) DEFAULT 100, -- maximum absolute difference between the two numbers (not in percentages)
    diff_in_perc_from numeric NOT NULL,
    diff_in_perc_to   numeric NOT NULL
);

GRANT SELECT ON matching.check_totals TO domonda_user;

COMMENT ON TABLE matching.check_totals IS '@name matchingCheckTotals';

----

CREATE TABLE matching.check_ibans (
    check_id uuid PRIMARY KEY REFERENCES matching.check (id) ON DELETE CASCADE
);

GRANT SELECT ON matching.check_ibans TO domonda_user;

COMMENT ON TABLE matching.check_ibans IS '@name matchingCheckIbans';

----

CREATE TABLE matching.check_invoice_or_order_number_in_purpose (
    check_id uuid PRIMARY KEY REFERENCES matching.check (id) ON DELETE CASCADE,

    min_len         int NOT NULL CHECK(min_len >= 3), -- minimum length of the `invoice_number` (applies also when `take_last_chars` is specified) to run the check against
    take_last_chars int CHECK(take_last_chars >= 3)  -- take last X number of chars from the `invoice_number` and check if it appears in the transaction purpose
);

GRANT SELECT ON matching.check_invoice_or_order_number_in_purpose TO domonda_user;

COMMENT ON TABLE matching.check_invoice_or_order_number_in_purpose IS '@name matchingCheckInvoiceOrOrderNumberInPurpose';

----

CREATE TABLE matching.check_dates (
    check_id uuid PRIMARY KEY REFERENCES matching.check (id) ON DELETE CASCADE,

    diff_in_days_from int NOT NULL,
    CONSTRAINT diff_in_days_from_check check(diff_in_days_from >= -28),
    diff_in_days_to   int NOT NULL,
    CONSTRAINT diff_in_days_to_check check(diff_in_days_to <= 365)
);

GRANT SELECT ON matching.check_dates TO domonda_user;

COMMENT ON TABLE matching.check_dates IS '@name matchingCheckDates';

----

CREATE TABLE matching.check_invoice_date_in_purpose (
    check_id uuid PRIMARY KEY REFERENCES matching.check (id) ON DELETE CASCADE,

    format text NOT NULL -- format of the `invoice_date` that should appear in the `transaction_purpose`
);

GRANT SELECT ON matching.check_invoice_date_in_purpose TO domonda_user;

COMMENT ON TABLE matching.check_invoice_date_in_purpose IS '@name matchingCheckInvoiceDateInPurpose';

----

CREATE TABLE matching.check_partner_names_similarity (
    check_id uuid PRIMARY KEY REFERENCES matching.check (id) ON DELETE CASCADE,

    min_len    int NOT NULL CHECK(min_len >= 3), -- minimum length of the `transaction_partner_name`
    similarity numeric NOT NULL
);

GRANT SELECT ON matching.check_partner_names_similarity TO domonda_user;

COMMENT ON TABLE matching.check_partner_names_similarity IS '@name matchingCheckPartnerNamesSimilarity';

----

-- TODO FIXME:

-- CREATE TYPE matching.check_type AS ENUM (
--     'TRANSACTION_TYPE',
--     'TOTALS',
--     'IBANS',
--     'INVOICE_OR_NUMBER_IN_PURPOSE',
--     'DATES',
--     'INVOICE_DATE_IN_PURPOSE',
--     'PARTNER_NAMES_SIMILARITY'
-- );

-- CREATE FUNCTION matching.type_of_check(check_id uuid) RETURNS matching.check_type
-- LANGUAGE SQL STABLE AS
-- $$
--     SELECT
--         CASE
--             WHEN transaction_type.check_id          IS NOT NULL THEN 'TRANSACTION_TYPE'::matching.check_type
--             WHEN totals.check_id                    IS NOT NULL THEN 'TOTALS'::matching.check_type
--             WHEN ibans.check_id                     IS NOT NULL THEN 'IBANS'::matching.check_type
--             WHEN invoice_number_in_purpose.check_id IS NOT NULL THEN 'INVOICE_OR_NUMBER_IN_PURPOSE'::matching.check_type
--             WHEN dates.check_id                     IS NOT NULL THEN 'DATES'::matching.check_type
--             WHEN invoice_date_in_purpose.check_id   IS NOT NULL THEN 'INVOICE_DATE_IN_PURPOSE'::matching.check_type
--             WHEN partner_names_similarity.check_id  IS NOT NULL THEN 'PARTNER_NAMES_SIMILARITY'::matching.check_type
--         END
--     FROM matching.check AS ck
--     LEFT JOIN matching.check_transaction_type AS transaction_type ON transaction_type.check_id = ck.id
--     LEFT JOIN matching.check_totals AS totals ON totals.check_id = ck.id
--     LEFT JOIN matching.check_ibans AS ibans ON ibans.check_id = ck.id
--     LEFT JOIN matching.check_invoice_or_order_number_in_purpose AS invoice_number_in_purpose ON invoice_number_in_purpose.check_id = ck.id
--     LEFT JOIN matching.check_dates AS dates ON dates.check_id = ck.id
--     LEFT JOIN matching.check_invoice_date_in_purpose AS invoice_date_in_purpose ON invoice_date_in_purpose.check_id = ck.id
--     LEFT JOIN matching.check_partner_names_similarity AS partner_names_similarity ON partner_names_similarity.check_id = ck.id
--     WHERE ck.id = type_of_check.check_id
-- $$;

-- CREATE FUNCTION matching.check_type(ck matching.check) RETURNS matching.check_type
-- LANGUAGE SQL STABLE AS
-- $$
--     SELECT matching.type_of_check(check_type.ck.id)
-- $$;

-- CREATE FUNCTION matching.check_types(check_id uuid) RETURNS matching.check_type[]
-- LANGUAGE plpgsql STABLE AS
-- $$
-- DECLARE
--     types matching.check_type[]
-- BEGIN
--     IF NOT EXISTS (SELECT 1 FROM api.client_company_tag WHERE (id = NEW.id)) THEN
--         RAISE EXCEPTION 'ClientCompanyTag "%" not found', NEW.id;
--     END IF;

--     SELECT
--         CASE
--             WHEN transaction_type.check_id          IS NOT NULL THEN 'TRANSACTION_TYPE'::matching.check_type
--             WHEN totals.check_id                    IS NOT NULL THEN 'TOTALS'::matching.check_type
--             WHEN ibans.check_id                     IS NOT NULL THEN 'IBANS'::matching.check_type
--             WHEN invoice_number_in_purpose.check_id IS NOT NULL THEN 'INVOICE_OR_NUMBER_IN_PURPOSE'::matching.check_type
--             WHEN dates.check_id                     IS NOT NULL THEN 'DATES'::matching.check_type
--             WHEN invoice_date_in_purpose.check_id   IS NOT NULL THEN 'INVOICE_DATE_IN_PURPOSE'::matching.check_type
--             WHEN partner_names_similarity.check_id  IS NOT NULL THEN 'PARTNER_NAMES_SIMILARITY'::matching.check_type
--         END
--     FROM matching.check AS ck
--     LEFT JOIN matching.check_transaction_type AS transaction_type ON transaction_type.check_id = ck.id
--     LEFT JOIN matching.check_totals AS totals ON totals.check_id = ck.id
--     LEFT JOIN matching.check_ibans AS ibans ON ibans.check_id = ck.id
--     LEFT JOIN matching.check_invoice_or_order_number_in_purpose AS invoice_number_in_purpose ON invoice_number_in_purpose.check_id = ck.id
--     LEFT JOIN matching.check_dates AS dates ON dates.check_id = ck.id
--     LEFT JOIN matching.check_invoice_date_in_purpose AS invoice_date_in_purpose ON invoice_date_in_purpose.check_id = ck.id
--     LEFT JOIN matching.check_partner_names_similarity AS partner_names_similarity ON partner_names_similarity.check_id = ck.id
--     WHERE ck.id = type_of_check.check_id
-- END
-- $$;