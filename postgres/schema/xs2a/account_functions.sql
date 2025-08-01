CREATE FUNCTION xs2a.connection_available_xs2a_accounts(
  "connection" xs2a."connection"
) RETURNS SETOF xs2a.account AS
$$
  SELECT * FROM xs2a.account WHERE connection_id = "connection".id
  ORDER BY
    (
      SELECT (
        SELECT EXISTS (SELECT 1 FROM public.bank_account WHERE xs2a_account_id = account.id)
      ) OR (
        SELECT EXISTS (SELECT 1 FROM public.credit_card_account WHERE xs2a_account_id = account.id)
      )
    ),
    description
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION xs2a.connection_available_xs2a_accounts IS E'@fieldName availableXs2AAccounts\n`Xs2AAccounts` from the `Xs2AConnection` which are available for usage.';

----

CREATE FUNCTION public.money_account_protected_xs2a_connection(
  money_account public.money_account
) RETURNS xs2a."connection" AS
$$
  SELECT c.* FROM xs2a."connection" AS c
    INNER JOIN xs2a.account AS a ON (a.connection_id = c.id)
  WHERE (
    a.id = money_account.xs2a_account_id
  )
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION public.money_account_protected_xs2a_connection IS 'The protected `Xs2AConnection` linked to the `MoneyAccount`.';

----

CREATE FUNCTION public.bank_account_protected_xs2a_bank_user(
  bank_account public.bank_account
) RETURNS xs2a.bank_user AS
$$
  SELECT bu.* FROM xs2a.bank_user AS bu
    INNER JOIN xs2a.account AS a ON (a.bank_user_id = bu.id)
  WHERE (
    a.id = bank_account.xs2a_account_id
  )
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION public.bank_account_protected_xs2a_bank_user IS 'The protected `Xs2ABankUser` linked to the `BankAccount`.';

----

CREATE FUNCTION public.bank_account_protected_xs2a_connection(
  bank_account public.bank_account
) RETURNS xs2a."connection" AS
$$
  SELECT c.* FROM xs2a."connection" AS c
    INNER JOIN xs2a.account AS a ON (a.connection_id = c.id)
  WHERE (
    a.id = bank_account.xs2a_account_id
  )
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION public.bank_account_protected_xs2a_connection IS 'The protected `Xs2AConnection` linked to the `BankAccount`.';

----

CREATE FUNCTION public.bank_account_protected_xs2a_connection_sync_active(
  bank_account public.bank_account
) RETURNS bool AS
$$
  SELECT c.sync_active FROM xs2a."connection" AS c
    INNER JOIN xs2a.account AS a ON (a.connection_id = c.id)
  WHERE (
    a.id = bank_account.xs2a_account_id
  )
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION public.bank_account_protected_xs2a_connection_sync_active IS 'The protected `Xs2AConnection.syncActive` linked to the `BankAccount`.';

----

CREATE FUNCTION public.credit_card_account_protected_xs2a_bank_user(
  credit_card_account public.credit_card_account
) RETURNS xs2a.bank_user AS
$$
  SELECT bu.* FROM xs2a.bank_user AS bu
    INNER JOIN xs2a.account AS a ON (a.bank_user_id = bu.id)
  WHERE (
    a.id = credit_card_account.xs2a_account_id
  )
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION public.credit_card_account_protected_xs2a_bank_user IS 'The protected `Xs2ABankUser` linked to the `CreditCardAccount`.';

----

CREATE FUNCTION public.credit_card_account_protected_xs2a_connection(
  credit_card_account public.credit_card_account
) RETURNS xs2a."connection" AS
$$
  SELECT c.* FROM xs2a."connection" AS c
    INNER JOIN xs2a.account AS a ON (a.connection_id = c.id)
  WHERE (
    a.id = credit_card_account.xs2a_account_id
  )
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION public.credit_card_account_protected_xs2a_connection IS 'The protected `Xs2AConnection` linked to the `CreditCardAccount`.';

----

CREATE FUNCTION public.credit_card_account_protected_xs2a_connection_sync_active(
  credit_card_account public.credit_card_account
) RETURNS bool AS
$$
  SELECT c.sync_active FROM xs2a."connection" AS c
    INNER JOIN xs2a.account AS a ON (a.connection_id = c.id)
  WHERE (
    a.id = credit_card_account.xs2a_account_id
  )
$$
LANGUAGE SQL STABLE SECURITY DEFINER;

COMMENT ON FUNCTION public.credit_card_account_protected_xs2a_connection_sync_active IS 'The protected `Xs2AConnection.syncActive` linked to the `CreditCardAccount`.';
