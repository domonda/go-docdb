-- public.document_money_transaction (
    -- document_id uuid NOT NULL REFERENCES public.document(id),
    -- money_transaction_id uuid NOT NULL REFERENCES public.money_transaction(id),
    -- created_by uuid REFERENCES public.user(id),
    -- check_id uuid REFERENCES matching.check(id),
    -- check_id_confirmed_by uuid REFERENCES public.user(id),
    -- check_id_confirmed_at timestamptz,
    ---- deprecated ----
    -- confidence float8 NOT NULL,
    -- confirmed_by uuid REFERENCES public.user(id),
    -- confirmed_at timestamptz,
    ---- ./deprecated ----
    -- updated_at updated_time NOT NULL,
    -- created_at created_time NOT NULL
-- )

create view public.document_money_transaction as
    (
        select
            document_id,
            bank_transaction_id as money_transaction_id,
            created_by,
            check_id,
            check_id_confirmed_by,
            check_id_confirmed_at,
            confidence,
            confirmed_by,
            confirmed_at,
            updated_at,
            created_at
        from public.document_bank_transaction
    ) union all (
        select
            document_id,
            credit_card_transaction_id as money_transaction_id,
            created_by,
            check_id,
            check_id_confirmed_by,
            check_id_confirmed_at,
            confidence,
            confirmed_by,
            confirmed_at,
            updated_at,
            created_at
        from public.document_credit_card_transaction
    ) union all (
        select
            document_id,
            cash_transaction_id as money_transaction_id,
            created_by,
            check_id,
            check_id_confirmed_by,
            check_id_confirmed_at,
            confidence,
            confirmed_by,
            confirmed_at,
            updated_at,
            created_at
        from public.document_cash_transaction
    );
    -- TODO-db-210419 add union for other transaction types

grant select on public.document_money_transaction to domonda_user;
grant select on public.document_money_transaction to domonda_wg_user;

comment on column public.document_money_transaction.document_id is '@nullable';
comment on column public.document_money_transaction.confidence is '@notNull';
comment on column public.document_money_transaction.updated_at is '@notNull';
comment on column public.document_money_transaction.created_at is '@notNull';
comment on view public.document_money_transaction is $$
@primaryKey document_id,money_transaction_id
@foreignKey (document_id) references public.document (id)
@foreignKey (money_transaction_id) references public.money_transaction (id)
@foreignKey (created_by) references public.user (id)
@foreignKey (check_id) references matching.check (id)
@foreignKey (check_id_confirmed_by) references public.user (id)
@foreignKey (confirmed_by) references public.user (id)
A `DocumentMoneyTransaction`. It abstracts over all supported forms of money related matches (`DocumentBankTransaction`, `DocumentCreditCardTransaction`, `DocumentCashTransaction`, `DocumentPaypalTransaction` or `DocumentStripeTransaction`).$$;

----

-- NOTE: this function is used from within Go
CREATE FUNCTION private.add_document_money_transaction(
    document_id          uuid,
    money_transaction_id uuid,
    created_by           uuid,
    check_id             uuid
) RETURNS public.document_money_transaction AS
$$
DECLARE
    added_document_money_transaction public.document_money_transaction;
BEGIN

    -- maybe bank_transaction
    IF EXISTS (SELECT 1 FROM public.bank_transaction WHERE id = add_document_money_transaction.money_transaction_id) THEN

        INSERT INTO public.document_bank_transaction (
            document_id,
            bank_transaction_id,
            created_by,
            check_id
        ) VALUES (
            add_document_money_transaction.document_id,
            add_document_money_transaction.money_transaction_id,
            add_document_money_transaction.created_by,
            add_document_money_transaction.check_id
        )
        RETURNING
            document_bank_transaction.document_id,
            document_bank_transaction.bank_transaction_id,
            document_bank_transaction.created_by,
            document_bank_transaction.check_id,
            document_bank_transaction.check_id_confirmed_by,
            document_bank_transaction.check_id_confirmed_at,
            document_bank_transaction.confidence,
            document_bank_transaction.confirmed_by,
            document_bank_transaction.confirmed_at,
            document_bank_transaction.updated_at,
            document_bank_transaction.created_at
        INTO added_document_money_transaction;

        -- drop money category
        update public.bank_transaction set money_category_id=null, updated_at=now()
        where bank_transaction.id = add_document_money_transaction.money_transaction_id;

        RETURN added_document_money_transaction;

    END IF;

    -- maybe credit_card_transaction
    IF EXISTS (SELECT 1 FROM public.credit_card_transaction WHERE id = add_document_money_transaction.money_transaction_id) THEN

        INSERT INTO public.document_credit_card_transaction (
            document_id,
            credit_card_transaction_id,
            created_by,
            check_id
        ) VALUES (
            add_document_money_transaction.document_id,
            add_document_money_transaction.money_transaction_id,
            add_document_money_transaction.created_by,
            add_document_money_transaction.check_id
        )
        RETURNING
            document_credit_card_transaction.document_id,
            document_credit_card_transaction.credit_card_transaction_id,
            document_credit_card_transaction.created_by,
            document_credit_card_transaction.check_id,
            document_credit_card_transaction.check_id_confirmed_by,
            document_credit_card_transaction.check_id_confirmed_at,
            document_credit_card_transaction.confidence,
            document_credit_card_transaction.confirmed_by,
            document_credit_card_transaction.confirmed_at,
            document_credit_card_transaction.updated_at,
            document_credit_card_transaction.created_at
        INTO added_document_money_transaction;

        -- drop money category
        update public.credit_card_transaction set money_category_id=null, updated_at=now()
        where credit_card_transaction.id = add_document_money_transaction.money_transaction_id;

        RETURN added_document_money_transaction;

    END IF;

    -- maybe cash_transaction
    IF EXISTS (SELECT 1 FROM public.cash_transaction WHERE id = add_document_money_transaction.money_transaction_id) THEN

        INSERT INTO public.document_cash_transaction (
            document_id,
            cash_transaction_id,
            created_by,
            check_id
        ) VALUES (
            add_document_money_transaction.document_id,
            add_document_money_transaction.money_transaction_id,
            add_document_money_transaction.created_by,
            add_document_money_transaction.check_id
        )
        RETURNING
            document_cash_transaction.document_id,
            document_cash_transaction.cash_transaction_id,
            document_cash_transaction.created_by,
            document_cash_transaction.check_id,
            document_cash_transaction.check_id_confirmed_by,
            document_cash_transaction.check_id_confirmed_at,
            document_cash_transaction.confidence,
            document_cash_transaction.confirmed_by,
            document_cash_transaction.confirmed_at,
            document_cash_transaction.updated_at,
            document_cash_transaction.created_at
        INTO added_document_money_transaction;

        -- drop money category
        update public.cash_transaction set money_category_id=null, updated_at=now()
        where cash_transaction.id = add_document_money_transaction.money_transaction_id;

        RETURN added_document_money_transaction;

    END IF;

    -- maybe paypal_transaction
    IF EXISTS (SELECT 1 FROM public.paypal_transaction WHERE id = add_document_money_transaction.money_transaction_id) THEN

        INSERT INTO public.document_paypal_transaction (
            document_id,
            paypal_transaction_id,
            created_by,
            check_id
        ) VALUES (
            add_document_money_transaction.document_id,
            add_document_money_transaction.money_transaction_id,
            add_document_money_transaction.created_by,
            add_document_money_transaction.check_id
        )
        RETURNING
            document_paypal_transaction.document_id,
            document_paypal_transaction.paypal_transaction_id,
            document_paypal_transaction.created_by,
            document_paypal_transaction.check_id,
            document_paypal_transaction.check_id_confirmed_by,
            document_paypal_transaction.check_id_confirmed_at,
            document_paypal_transaction.confidence,
            document_paypal_transaction.confirmed_by,
            document_paypal_transaction.confirmed_at,
            document_paypal_transaction.updated_at,
            document_paypal_transaction.created_at
        INTO added_document_money_transaction;

        -- drop money category
        update public.paypal_transaction set money_category_id=null, updated_at=now()
        where paypal_transaction.id = add_document_money_transaction.money_transaction_id;

        RETURN added_document_money_transaction;

    END IF;

    -- maybe stripe_transaction
    IF EXISTS (SELECT 1 FROM public.stripe_transaction WHERE id = add_document_money_transaction.money_transaction_id) THEN

        INSERT INTO public.document_stripe_transaction (
            document_id,
            paypal_transaction_id,
            created_by,
            check_id
        ) VALUES (
            add_document_money_transaction.document_id,
            add_document_money_transaction.money_transaction_id,
            add_document_money_transaction.created_by,
            add_document_money_transaction.check_id
        )
        RETURNING
            document_stripe_transaction.document_id,
            document_stripe_transaction.stripe_transaction_id,
            document_stripe_transaction.created_by,
            document_stripe_transaction.check_id,
            document_stripe_transaction.check_id_confirmed_by,
            document_stripe_transaction.check_id_confirmed_at,
            document_stripe_transaction.confidence,
            document_stripe_transaction.confirmed_by,
            document_stripe_transaction.confirmed_at,
            document_stripe_transaction.updated_at,
            document_stripe_transaction.created_at
        INTO added_document_money_transaction;

        -- drop money category
        update public.stripe_transaction set money_category_id=null, updated_at=now()
        where stripe_transaction.id = add_document_money_transaction.money_transaction_id;

        RETURN added_document_money_transaction;

    END IF;

END;
$$
LANGUAGE plpgsql VOLATILE;

----

CREATE FUNCTION public.add_document_money_transaction(
    document_id          uuid,
    money_transaction_id uuid
) RETURNS public.document_money_transaction AS
$$
    SELECT * FROM private.add_document_money_transaction(
        add_document_money_transaction.document_id,
        add_document_money_transaction.money_transaction_id,
        (SELECT id FROM private.current_user()),
        null
    )
$$
LANGUAGE SQL VOLATILE STRICT;

----

CREATE FUNCTION public.add_document_money_transactions(
    document_id           uuid,
    money_transaction_ids uuid[]
) RETURNS SETOF public.document_money_transaction AS
$$
    SELECT added_document_money_transaction.* FROM
        UNNEST(add_document_money_transactions.money_transaction_ids) AS money_transaction_id,
        public.add_document_money_transaction(add_document_money_transactions.document_id, money_transaction_id) AS added_document_money_transaction
$$
LANGUAGE SQL VOLATILE STRICT;

----

CREATE FUNCTION public.delete_document_money_transaction(
    document_id          uuid,
    money_transaction_id uuid
) RETURNS public.document_money_transaction AS
$$
DECLARE
    document_money_transaction public.document_money_transaction;
BEGIN

    -- maybe document_bank_transaction
    SELECT
        dmt.document_id,
        dmt.bank_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.confidence,
        dmt.confirmed_by,
        dmt.confirmed_at,
        dmt.updated_at,
        dmt.created_at
    INTO document_money_transaction
    FROM public.document_bank_transaction AS dmt WHERE (
        dmt.document_id = delete_document_money_transaction.document_id
    ) AND (
        dmt.bank_transaction_id = delete_document_money_transaction.money_transaction_id
    );
    IF NOT (document_money_transaction IS NULL) THEN

        DELETE FROM public.document_bank_transaction AS dmt
        WHERE (
            dmt.document_id = delete_document_money_transaction.document_id
        ) AND (
            dmt.bank_transaction_id = delete_document_money_transaction.money_transaction_id
        );

        RETURN document_money_transaction;

    END IF;

    -- maybe document_credit_card_transaction
    SELECT
        dmt.document_id,
        dmt.credit_card_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.confidence,
        dmt.confirmed_by,
        dmt.confirmed_at,
        dmt.updated_at,
        dmt.created_at
    INTO document_money_transaction
    FROM public.document_credit_card_transaction AS dmt WHERE (
        dmt.document_id = delete_document_money_transaction.document_id
    ) AND (
        dmt.credit_card_transaction_id = delete_document_money_transaction.money_transaction_id
    );
    IF NOT (document_money_transaction IS NULL) THEN

        DELETE FROM public.document_credit_card_transaction AS dmt
        WHERE (
            dmt.document_id = delete_document_money_transaction.document_id
        ) AND (
            dmt.credit_card_transaction_id = delete_document_money_transaction.money_transaction_id
        );

        RETURN document_money_transaction;

    END IF;

    -- maybe document_cash_transaction
    SELECT
        dmt.document_id,
        dmt.cash_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.confidence,
        dmt.confirmed_by,
        dmt.confirmed_at,
        dmt.updated_at,
        dmt.created_at
    INTO document_money_transaction
    FROM public.document_cash_transaction AS dmt WHERE (
        dmt.document_id = delete_document_money_transaction.document_id
    ) AND (
        dmt.cash_transaction_id = delete_document_money_transaction.money_transaction_id
    );
    IF NOT (document_money_transaction IS NULL) THEN

        DELETE FROM public.document_cash_transaction AS dmt
        WHERE (
            dmt.document_id = delete_document_money_transaction.document_id
        ) AND (
            dmt.cash_transaction_id = delete_document_money_transaction.money_transaction_id
        );

        RETURN document_money_transaction;

    END IF;

    -- maybe document_paypal_transaction
    SELECT
        dmt.document_id,
        dmt.paypal_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.confidence,
        dmt.confirmed_by,
        dmt.confirmed_at,
        dmt.updated_at,
        dmt.created_at
    INTO document_money_transaction
    FROM public.document_paypal_transaction AS dmt WHERE (
        dmt.document_id = delete_document_money_transaction.document_id
    ) AND (
        dmt.paypal_transaction_id = delete_document_money_transaction.money_transaction_id
    );
    IF NOT (document_money_transaction IS NULL) THEN

        DELETE FROM public.document_paypal_transaction AS dmt
        WHERE (
            dmt.document_id = delete_document_money_transaction.document_id
        ) AND (
            dmt.paypal_transaction_id = delete_document_money_transaction.money_transaction_id
        );

        RETURN document_money_transaction;

    END IF;

    -- maybe document_stripe_transaction
    SELECT
        dmt.document_id,
        dmt.stripe_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.confidence,
        dmt.confirmed_by,
        dmt.confirmed_at,
        dmt.updated_at,
        dmt.created_at
    INTO document_money_transaction
    FROM public.document_stripe_transaction AS dmt WHERE (
        dmt.document_id = delete_document_money_transaction.document_id
    ) AND (
        dmt.stripe_transaction_id = delete_document_money_transaction.money_transaction_id
    );
    IF NOT (document_money_transaction IS NULL) THEN

        DELETE FROM public.document_stripe_transaction AS dmt
        WHERE (
            dmt.document_id = delete_document_money_transaction.document_id
        ) AND (
            dmt.stripe_transaction_id = delete_document_money_transaction.money_transaction_id
        );

        RETURN document_money_transaction;

    END IF;

END;
$$
LANGUAGE plpgsql VOLATILE STRICT;

----

CREATE FUNCTION private.update_document_money_transaction_check_id(
    document_id          uuid,
    money_transaction_id uuid,
    check_id             uuid
) RETURNS public.document_money_transaction AS
$$
DECLARE
    document_money_transaction public.document_money_transaction;
BEGIN

    -- maybe document_bank_transaction
    SELECT
        dmt.document_id,
        dmt.bank_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.confidence,
        dmt.confirmed_by,
        dmt.confirmed_at,
        dmt.updated_at,
        dmt.created_at
    INTO document_money_transaction
    FROM public.document_bank_transaction AS dmt WHERE (
        dmt.document_id = update_document_money_transaction_check_id.document_id
    ) AND (
        dmt.bank_transaction_id = update_document_money_transaction_check_id.money_transaction_id
    );
    IF NOT (document_money_transaction IS NULL) THEN

        UPDATE public.document_bank_transaction AS dmt
            SET
                check_id=update_document_money_transaction_check_id.check_id,
                updated_at=now()
        WHERE (
            dmt.document_id = update_document_money_transaction_check_id.document_id
        ) AND (
            dmt.bank_transaction_id = update_document_money_transaction_check_id.money_transaction_id
        )
        RETURNING
            dmt.document_id,
            dmt.bank_transaction_id,
            dmt.created_by,
            dmt.check_id,
            dmt.check_id_confirmed_by,
            dmt.check_id_confirmed_at,
            dmt.confidence,
            dmt.confirmed_by,
            dmt.confirmed_at,
            dmt.updated_at,
            dmt.created_at
        INTO document_money_transaction;

        RETURN document_money_transaction;

    END IF;

    -- maybe document_credit_card_transaction
    SELECT
        dmt.document_id,
        dmt.credit_card_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.confidence,
        dmt.confirmed_by,
        dmt.confirmed_at,
        dmt.updated_at,
        dmt.created_at
    INTO document_money_transaction
    FROM public.document_credit_card_transaction AS dmt WHERE (
        dmt.document_id = update_document_money_transaction_check_id.document_id
    ) AND (
        dmt.credit_card_transaction_id = update_document_money_transaction_check_id.money_transaction_id
    );
    IF NOT (document_money_transaction IS NULL) THEN

        UPDATE public.document_credit_card_transaction AS dmt
            SET
                check_id=update_document_money_transaction_check_id.check_id,
                updated_at=now()
        WHERE (
            dmt.document_id = update_document_money_transaction_check_id.document_id
        ) AND (
            dmt.credit_card_transaction_id = update_document_money_transaction_check_id.money_transaction_id
        )
        RETURNING
            dmt.document_id,
            dmt.credit_card_transaction_id,
            dmt.created_by,
            dmt.check_id,
            dmt.check_id_confirmed_by,
            dmt.check_id_confirmed_at,
            dmt.confidence,
            dmt.confirmed_by,
            dmt.confirmed_at,
            dmt.updated_at,
            dmt.created_at
        INTO document_money_transaction;

        RETURN document_money_transaction;

    END IF;

    -- maybe document_cash_transaction
    SELECT
        dmt.document_id,
        dmt.cash_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.confidence,
        dmt.confirmed_by,
        dmt.confirmed_at,
        dmt.updated_at,
        dmt.created_at
    INTO document_money_transaction
    FROM public.document_cash_transaction AS dmt WHERE (
        dmt.document_id = update_document_money_transaction_check_id.document_id
    ) AND (
        dmt.cash_transaction_id = update_document_money_transaction_check_id.money_transaction_id
    );
    IF NOT (document_money_transaction IS NULL) THEN

        UPDATE public.document_cash_transaction AS dmt
            SET
                check_id=update_document_money_transaction_check_id.check_id,
                updated_at=now()
        WHERE (
            dmt.document_id = update_document_money_transaction_check_id.document_id
        ) AND (
            dmt.cash_transaction_id = update_document_money_transaction_check_id.money_transaction_id
        )
        RETURNING
            dmt.document_id,
            dmt.cash_transaction_id,
            dmt.created_by,
            dmt.check_id,
            dmt.check_id_confirmed_by,
            dmt.check_id_confirmed_at,
            dmt.confidence,
            dmt.confirmed_by,
            dmt.confirmed_at,
            dmt.updated_at,
            dmt.created_at
        INTO document_money_transaction;

        RETURN document_money_transaction;

    END IF;

    -- maybe document_paypal_transaction
    SELECT
        dmt.document_id,
        dmt.paypal_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.confidence,
        dmt.confirmed_by,
        dmt.confirmed_at,
        dmt.updated_at,
        dmt.created_at
    INTO document_money_transaction
    FROM public.document_paypal_transaction AS dmt WHERE (
        dmt.document_id = update_document_money_transaction_check_id.document_id
    ) AND (
        dmt.paypal_transaction_id = update_document_money_transaction_check_id.money_transaction_id
    );
    IF NOT (document_money_transaction IS NULL) THEN

        UPDATE public.document_paypal_transaction AS dmt
            SET
                check_id=update_document_money_transaction_check_id.check_id,
                updated_at=now()
        WHERE (
            dmt.document_id = update_document_money_transaction_check_id.document_id
        ) AND (
            dmt.paypal_transaction_id = update_document_money_transaction_check_id.money_transaction_id
        )
        RETURNING
            dmt.document_id,
            dmt.paypal_transaction_id,
            dmt.created_by,
            dmt.check_id,
            dmt.check_id_confirmed_by,
            dmt.check_id_confirmed_at,
            dmt.confidence,
            dmt.confirmed_by,
            dmt.confirmed_at,
            dmt.updated_at,
            dmt.created_at
        INTO document_money_transaction;

        RETURN document_money_transaction;

    END IF;

    -- maybe document_stripe_transaction
    SELECT
        dmt.document_id,
        dmt.stripe_transaction_id,
        dmt.created_by,
        dmt.check_id,
        dmt.check_id_confirmed_by,
        dmt.check_id_confirmed_at,
        dmt.confidence,
        dmt.confirmed_by,
        dmt.confirmed_at,
        dmt.updated_at,
        dmt.created_at
    INTO document_money_transaction
    FROM public.document_stripe_transaction AS dmt WHERE (
        dmt.document_id = update_document_money_transaction_check_id.document_id
    ) AND (
        dmt.stripe_transaction_id = update_document_money_transaction_check_id.money_transaction_id
    );
    IF NOT (document_money_transaction IS NULL) THEN

        UPDATE public.document_stripe_transaction AS dmt
            SET
                check_id=update_document_money_transaction_check_id.check_id,
                updated_at=now()
        WHERE (
            dmt.document_id = update_document_money_transaction_check_id.document_id
        ) AND (
            dmt.stripe_transaction_id = update_document_money_transaction_check_id.money_transaction_id
        )
        RETURNING
            dmt.document_id,
            dmt.stripe_transaction_id,
            dmt.created_by,
            dmt.check_id,
            dmt.check_id_confirmed_by,
            dmt.check_id_confirmed_at,
            dmt.confidence,
            dmt.confirmed_by,
            dmt.confirmed_at,
            dmt.updated_at,
            dmt.created_at
        INTO document_money_transaction;

        RETURN document_money_transaction;

    END IF;

END;
$$
LANGUAGE plpgsql VOLATILE STRICT;

----

create function public.money_transaction_document_money_transaction_by_document_id(
    money_transaction public.money_transaction,
    document_id       uuid
) returns public.document_money_transaction as
$$
    select * from public.document_money_transaction
    where (
        money_transaction_id = money_transaction.id
    ) and (
        document_id = money_transaction_document_money_transaction_by_document_id.document_id
    )
$$
language sql stable;
