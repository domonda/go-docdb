CREATE TABLE xs2a."connection" (
  id text PRIMARY KEY,

  bank_user_id text NOT NULL REFERENCES xs2a.bank_user(id) ON DELETE CASCADE,

  transaction text,

  bank_bic        bank_bic NOT NULL,
  bank_name       text NOT NULL,
  bank_country_id text NOT NULL,

  account_selection text NOT NULL DEFAULT 'all',
  sync_mode         text NOT NULL,
  sync_active       boolean NOT NULL,
  sync_message      text NOT NULL, -- if sync_message is empty, it will be: '' (not null)
  sync_fail_counter int NOT NULL,
  last_synced       timestamptz NOT NULL,

  updated_at  updated_time NOT NULL,
  created_at  created_time NOT NULL
);

COMMENT ON TABLE xs2a."connection" IS E'@name xs2aConnection';

GRANT SELECT ON xs2a."connection" TO domonda_user;
