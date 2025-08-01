CREATE TABLE xs2a.bank_user (
  id text PRIMARY KEY,

  user_id uuid NOT NULL UNIQUE REFERENCES public.user(id) ON DELETE CASCADE, -- the fintecsystems sync will take care of removing the user from their store

  name  text NOT NULL,
  email text NOT NULL UNIQUE,

  updated_at  updated_time NOT NULL,
  created_at  created_time NOT NULL
);

CREATE INDEX bank_user_user_id_idx ON xs2a.bank_user (user_id);

COMMENT ON TABLE xs2a.bank_user IS E'@name xs2aBankUser';

GRANT SELECT ON xs2a.bank_user TO domonda_user;

----

CREATE FUNCTION xs2a.bank_user_by_current_user_id()
RETURNS xs2a.bank_user AS
$$
  SELECT * FROM xs2a.bank_user WHERE (user_id = (SELECT id FROM private.current_user()))
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION xs2a.bank_user_by_current_user_id IS E'@name xs2aBankUserByCurrentUserId\nRetrieves the `Xs2ABankUser` for the currently authenticated user.';
