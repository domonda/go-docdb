CREATE TABLE private.document_version_abacus_data (
  document_version_id uuid PRIMARY KEY REFERENCES docdb.document_version(id) ON DELETE CASCADE,

  file_id          bigint,
  file_process_id  bigint,
  file_invoice_ids bigint[],
  file_state       bigint,
  file_pages       bigint,

  invoice_id                 bigint,
  document_uuid              uuid,
  invoice_duplicate_ids      bigint[],
  invoice_process_id         bigint,
  invoice_file_ids           bigint[],
  invoice_batch_id           bigint,
  invoice_verification_level bigint,
  invoice_was_exported       boolean,
  invoice_pages              bigint,

  account_numbers    text[],
  booking_name       text,
  booking_type       uuid,
  booking_texts      text[], -- Per invoice item if text has length
  num_invoice_items  int,
  invoice_date       text,
  invoice_no         text,
  partner            uuid,
  partner_name       text,
  partner_no         text,
  total_gross_amount float8,
  total_net_amount   float8,
  vat_id             text,
  currency           text,

  updated_at updated_time NOT NULL,
  created_at created_time NOT NULL
);

GRANT SELECT ON private.document_version_abacus_data TO domonda_user;

CREATE INDEX document_version_abacus_data_invoice_verification_level_idx ON private.document_version_abacus_data (invoice_verification_level);

COMMENT ON TYPE private.document_version_abacus_data IS 'Abacus data for a document version';

----

-- CREATE FUNCTION public.invoice_abacus_verification_level(
--   invoice public.invoice
-- ) RETURNS bigint AS
-- $$
--   SELECT dvad.invoice_verification_level FROM private.document_version_abacus_data AS dvad
--     INNER JOIN docdb.document_version AS dv ON (dv.id = dvad.document_version_id)
--   WHERE (
--     dv.document_id = invoice_abacus_verification_level.invoice.document_id
--   )
--   ORDER BY dv.version DESC
--   LIMIT 1
-- $$
-- LANGUAGE SQL STABLE;

-- COMMENT ON FUNCTION public.invoice_abacus_verification_level IS 'Verification level of the `Invoice` at abacus.';

----

-- CREATE TYPE public.abacus_verification_state AS ENUM (
--   'CANNOT_VERIFY', -- -10
--   'UNCONFIRMED',   -- 0
--   'PROCESSING',    -- 10
--   'ACCOUNTING',    -- 20
--   'COUNSELING',    -- 30
--   'UNKNOWN'        -- any other number
-- );

-- CREATE FUNCTION public.invoice_abacus_verification_state(
--   invoice public.invoice
-- ) RETURNS public.abacus_verification_state AS
-- $$
--   SELECT
--     CASE (public.invoice_abacus_verification_level(invoice_abacus_verification_state.invoice))
--       WHEN -10 THEN 'CANNOT_VERIFY'::public.abacus_verification_state
--       WHEN 0 THEN 'UNCONFIRMED'::public.abacus_verification_state
--       WHEN 10 THEN 'PROCESSING'::public.abacus_verification_state
--       WHEN 20 THEN 'ACCOUNTING'::public.abacus_verification_state
--       WHEN 30 THEN 'COUNSELING'::public.abacus_verification_state
--       ELSE 'UNKNOWN'::public.abacus_verification_state
--     END
-- $$
-- LANGUAGE SQL STABLE;

-- COMMENT ON FUNCTION public.invoice_abacus_verification_level IS 'Derived verification state of the `Invoice` at abacus.';
