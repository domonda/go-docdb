CREATE TABLE rule.invoice_reaction (
    reaction_id uuid PRIMARY KEY REFERENCES rule.reaction(id) ON DELETE CASCADE,

    change_currency boolean NOT NULL DEFAULT false,
    currency        public.currency_code,

    change_payment_status boolean NOT NULL DEFAULT false,
    payment_status        public.invoice_payment_status,

    change_due_date_from_invoice_date_in_days boolean NOT NULL DEFAULT false,
    due_date_from_invoice_date_in_days        int CHECK (due_date_from_invoice_date_in_days >= 0),

    change_discount_percent boolean NOT NULL DEFAULT false,
    discount_percent        float8 CHECK (discount_percent >= 0 AND discount_percent <= 100),

    change_discount_until_from_invoice_date_in_days boolean NOT NULL DEFAULT false,
    discount_until_from_invoice_date_in_days        int CHECK (discount_until_from_invoice_date_in_days >= 0),

    change_iban boolean NOT NULL DEFAULT false,
    iban        public.bank_iban,

    change_bic boolean NOT NULL DEFAULT false,
    bic        public.bank_bic,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT ALL ON rule.invoice_reaction TO domonda_user;
grant select on rule.invoice_reaction to domonda_wg_user;

----

create function rule.check_invoice_reaction_is_used()
returns trigger as $$
declare
    rec rule.invoice_reaction;
begin
    if TG_OP = 'DELETE' then
        rec = OLD;
    else
        rec = NEW;
    end if;

    if exists (select from rule.action_reaction
        where action_reaction.reaction_id = rec.reaction_id)
    and not rule.current_user_is_special()
    then
        raise exception 'Reaction is in use';
    end if;

    return rec;
end
$$ language plpgsql stable;

create trigger rule_check_invoice_reaction_is_used_trigger
    before insert or update or delete
    on rule.invoice_reaction
    for each row
    execute procedure rule.check_invoice_reaction_is_used();

----

CREATE FUNCTION rule.create_invoice_reaction(
    reaction_id                                     uuid,
    change_currency                                 boolean,
    change_payment_status                           boolean,
    change_due_date_from_invoice_date_in_days       boolean,
    change_discount_percent                         boolean,
    change_discount_until_from_invoice_date_in_days boolean,
    change_iban                                     boolean,
    change_bic                                      boolean,
    currency                                        public.currency_code = NULL,
    payment_status                                  public.invoice_payment_status = NULL,
    due_date_from_invoice_date_in_days              int = NULL,
    discount_percent                                float8 = NULL,
    discount_until_from_invoice_date_in_days        int = NULL,
    iban                                            public.bank_iban = NULL,
    bic                                             public.bank_bic = NULL
) RETURNS rule.invoice_reaction AS
$$
    INSERT INTO rule.invoice_reaction (
        reaction_id,
        change_currency,
        currency,
        change_payment_status,
        payment_status,
        change_due_date_from_invoice_date_in_days,
        due_date_from_invoice_date_in_days,
        change_discount_percent,
        discount_percent,
        change_discount_until_from_invoice_date_in_days,
        discount_until_from_invoice_date_in_days,
        change_iban,
        iban,
        change_bic,
        bic,
        created_by
    ) VALUES (
        create_invoice_reaction.reaction_id,
        create_invoice_reaction.change_currency,
        create_invoice_reaction.currency,
        create_invoice_reaction.change_payment_status,
        create_invoice_reaction.payment_status,
        create_invoice_reaction.change_due_date_from_invoice_date_in_days,
        create_invoice_reaction.due_date_from_invoice_date_in_days,
        create_invoice_reaction.change_discount_percent,
        create_invoice_reaction.discount_percent,
        create_invoice_reaction.change_discount_until_from_invoice_date_in_days,
        create_invoice_reaction.discount_until_from_invoice_date_in_days,
        create_invoice_reaction.change_iban,
        create_invoice_reaction.iban,
        create_invoice_reaction.change_bic,
        create_invoice_reaction.bic,
        private.current_user_id()
    )
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.update_invoice_reaction(
    reaction_id                                     uuid,
    change_currency                                 boolean,
    change_payment_status                           boolean,
    change_due_date_from_invoice_date_in_days       boolean,
    change_discount_percent                         boolean,
    change_discount_until_from_invoice_date_in_days boolean,
    change_iban                                     boolean,
    change_bic                                      boolean,
    currency                                        public.currency_code = NULL,
    payment_status                                  public.invoice_payment_status = NULL,
    due_date_from_invoice_date_in_days              int = NULL,
    discount_percent                                float8 = NULL,
    discount_until_from_invoice_date_in_days        int = NULL,
    iban                                            public.bank_iban = NULL,
    bic                                             public.bank_bic = NULL
) RETURNS rule.invoice_reaction AS
$$
    UPDATE rule.invoice_reaction
        SET
            change_currency=update_invoice_reaction.change_currency,
            currency=update_invoice_reaction.currency,
            change_payment_status=update_invoice_reaction.change_payment_status,
            payment_status=update_invoice_reaction.payment_status,
            change_due_date_from_invoice_date_in_days=update_invoice_reaction.change_due_date_from_invoice_date_in_days,
            due_date_from_invoice_date_in_days=update_invoice_reaction.due_date_from_invoice_date_in_days,
            change_discount_percent=update_invoice_reaction.change_discount_percent,
            discount_percent=update_invoice_reaction.discount_percent,
            change_discount_until_from_invoice_date_in_days=update_invoice_reaction.change_discount_until_from_invoice_date_in_days,
            discount_until_from_invoice_date_in_days=update_invoice_reaction.discount_until_from_invoice_date_in_days,
            change_iban=update_invoice_reaction.change_iban,
            iban=update_invoice_reaction.iban,
            change_bic=update_invoice_reaction.change_bic,
            bic=update_invoice_reaction.bic,
            updated_by=private.current_user_id(),
            updated_at=now()
    WHERE reaction_id = update_invoice_reaction.reaction_id
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.delete_invoice_reaction(
    reaction_id uuid
) RETURNS rule.invoice_reaction AS
$$
    DELETE FROM rule.invoice_reaction
    WHERE reaction_id = delete_invoice_reaction.reaction_id
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;

----

CREATE FUNCTION rule.do_invoice_reaction(
    invoice_reaction rule.invoice_reaction,
    invoice          public.invoice
) RETURNS public.invoice AS
$$
BEGIN

    IF invoice_reaction.change_currency = true THEN
        invoice.currency = invoice_reaction.currency;
        invoice.currency_confirmed_by = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'; -- Rule
        invoice.currency_confirmed_at = now();
    END IF;

    IF invoice_reaction.change_payment_status = true THEN
        invoice.payment_status = invoice_reaction.payment_status;
        invoice.payment_status_confirmed_by = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'; -- Rule
        invoice.payment_status_confirmed_at = now();
    END IF;

    IF invoice_reaction.change_due_date_from_invoice_date_in_days = true THEN
        invoice.due_date = invoice.invoice_date + make_interval(days => invoice_reaction.due_date_from_invoice_date_in_days);
        invoice.due_date_confirmed_by = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'; -- Rule
        invoice.due_date_confirmed_at = now();
    END IF;

    IF invoice_reaction.change_discount_percent = true THEN
        invoice.discount_percent = invoice_reaction.discount_percent;
        invoice.discount_percent_confirmed_by = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'; -- Rule
        invoice.discount_percent_confirmed_at = now();
    END IF;

    IF invoice_reaction.change_discount_until_from_invoice_date_in_days = true THEN
        invoice.discount_until = invoice.invoice_date + make_interval(days => invoice_reaction.discount_until_from_invoice_date_in_days);
        invoice.discount_until_confirmed_by = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'; -- Rule
        invoice.discount_until_confirmed_at = now();
    END IF;

    IF invoice_reaction.change_iban = true THEN
        invoice.iban = invoice_reaction.iban;
        invoice.iban_confirmed_by = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'; -- Rule
        invoice.iban_confirmed_at = now();
    END IF;

    IF invoice_reaction.change_bic = true THEN
        invoice.bic = invoice_reaction.bic;
        invoice.bic_confirmed_by = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'; -- Rule
        invoice.bic_confirmed_at = now();
    END IF;

    RETURN invoice;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

COMMENT ON FUNCTION rule.do_invoice_reaction IS '@omit';

----

CREATE FUNCTION rule.do_invoice_action_reaction(
    action_reaction rule.action_reaction,
    invoice         public.invoice
) RETURNS public.invoice AS
$$
DECLARE
    invoice_reaction rule.invoice_reaction;
BEGIN
    if action_reaction."trigger" in ('ALWAYS', 'ONCE', 'DOCUMENT_CHANGED')
    and exists(select from rule.invoice_log
        where invoice_log.action_reaction_id = action_reaction.id
        and invoice_log.invoice_document_id = invoice.document_id
        and (action_reaction."trigger" = 'ONCE'
            -- some triggers should not execute multiple times recursively
            or invoice_log.created_at = now())
        )
    then
        return invoice;
    end if;

    -- find reaction
    SELECT * INTO invoice_reaction FROM rule.invoice_reaction WHERE reaction_id = action_reaction.reaction_id;

    -- if there is no reaction, return
    IF invoice_reaction IS NULL THEN
        RETURN invoice;
    END IF;

    -- react
    invoice = rule.do_invoice_reaction(invoice_reaction, invoice);

    -- log
    INSERT INTO rule.invoice_log (action_reaction_id, invoice_document_id)
        VALUES (action_reaction.id, invoice.document_id);

    RETURN invoice;
END
$$
LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION rule.do_invoice_action_reaction IS '@omit';
