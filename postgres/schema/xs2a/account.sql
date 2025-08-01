CREATE TABLE xs2a.account (
  id text PRIMARY KEY,

  bank_user_id  text NOT NULL REFERENCES xs2a.bank_user(id) ON DELETE CASCADE,
  connection_id text REFERENCES xs2a."connection"(id) ON DELETE SET NULL,

  bank_name       text NOT NULL,
  bank_code       text NOT NULL,
  bank_bic        bank_bic NOT NULL,
  bank_country_id text NOT NULl,

  iban                 bank_iban,
  holder               text,
  CONSTRAINT holder_check CHECK(LENGTH(TRIM(holder)) > 0),
  description          text,
  CONSTRAINT description_check CHECK(LENGTH(TRIM(description)) > 0),
  account_number       text,
  CONSTRAINT account_number_check CHECK(LENGTH(TRIM(account_number)) > 0),
  joint_account        boolean NOT NULL,
  transaction_possible boolean NOT NULL,
  "type"               text NOT NULL, -- TODO: covert to ENUM when all possible account types are known

  updated_at  updated_time NOT NULL,
  created_at  created_time NOT NULL
);

COMMENT ON TABLE xs2a.account IS E'@name xs2aAccount';

GRANT SELECT ON xs2a.account TO domonda_user;

----

create function xs2a.account_is_wallet(
  account xs2a.account
) returns boolean as $$
  select account."type" = 'wallet'
$$ language sql immutable;

comment on function xs2a.account_is_wallet is '@notNull';

----

create function xs2a.account_is_credit_card(
  account xs2a.account
) returns boolean as $$
  select account."type" = 'creditcard' or account.iban is null
  or xs2a.account_is_wallet(account) -- wallet account types are imported to credit-cards, for now...
$$ language sql immutable;

comment on function xs2a.account_is_credit_card is '@notNull';

----

create function xs2a.account_derived_name(
  account xs2a.account
) returns text as $$
  select coalesce(
    nullif(trim(account.description), ''),
    case when xs2a.account_is_credit_card(account) then coalesce(nullif(trim(account.account_number), ''), account.iban) else account.iban end,
    nullif(trim(account.holder), ''),
    account.id
  )
$$ language sql immutable;

comment on function xs2a.account_derived_name is '@notNull';
