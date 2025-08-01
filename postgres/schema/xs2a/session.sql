CREATE TYPE xs2a.session_type AS ENUM (
  'API',  -- `xs2a.api`
  'PAY'   -- `xs2a.pay`
);

----

CREATE TABLE xs2a."session" (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

  user_id uuid NOT NULL REFERENCES public.user(id) ON DELETE CASCADE,

  "type"             xs2a.session_type NOT NULL,
  "transaction"      text NOT NULL,
  wizard_session_key text NOT NULL,

  finished bool NOT NULL DEFAULT false,

  -- check ensures that the `bank_payment_id` is always provided when the session type is `PAY`
  bank_payment_id uuid CHECK(("type" = 'PAY') = (bank_payment_id IS NOT NULL)) REFERENCES public.bank_payment(id) ON DELETE CASCADE, -- we want to retain as much sessions as possible (for debugging reasons)

  updated_at  updated_time NOT NULL,
  created_at  created_time NOT NULL
);

comment on table xs2a."session" is '@omit';
