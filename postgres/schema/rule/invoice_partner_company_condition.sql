CREATE TABLE rule.invoice_partner_company_condition (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    action_id uuid NOT NULL REFERENCES rule.action(id) ON DELETE CASCADE,

    partner_company_id_equality rule.equality_operator NOT NULL,
    partner_company_id          uuid REFERENCES public.partner_company(id) ON DELETE CASCADE,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT ALL ON rule.invoice_partner_company_condition TO domonda_user;
grant select on rule.invoice_partner_company_condition to domonda_wg_user;

CREATE UNIQUE INDEX rule_invoice_partner_company_condition_unique ON rule.invoice_partner_company_condition (action_id, partner_company_id);
CREATE UNIQUE INDEX rule_invoice_partner_company_condition_unique_null ON rule.invoice_partner_company_condition (action_id) WHERE (partner_company_id IS NULL);

CREATE INDEX rule_invoice_partner_company_condition_action_id_idx ON rule.invoice_partner_company_condition (action_id);

----

create function rule.check_invoice_partner_company_condition_is_used()
returns trigger as $$
declare
    rec rule.invoice_partner_company_condition;
begin
    if TG_OP = 'DELETE' then
        rec = OLD;
    else
        rec = NEW;
    end if;

    if exists (select from rule.action_reaction
        where action_reaction.action_id = rec.action_id)
    and not rule.current_user_is_special()
    then
        raise exception 'Action is in use';
    end if;

    return rec;
end
$$ language plpgsql stable;

create trigger rule_check_invoice_partner_company_condition_is_used_trigger
    before insert or update or delete
    on rule.invoice_partner_company_condition
    for each row
    execute procedure rule.check_invoice_partner_company_condition_is_used();

----

CREATE FUNCTION rule.create_invoice_partner_company_condition (
    action_id                   uuid,
    partner_company_id_equality rule.equality_operator,
    partner_company_id          uuid = NULL
) RETURNS rule.invoice_partner_company_condition AS
$$
    INSERT INTO rule.invoice_partner_company_condition (action_id, partner_company_id_equality, partner_company_id, created_by)
        VALUES (create_invoice_partner_company_condition.action_id, create_invoice_partner_company_condition.partner_company_id_equality, create_invoice_partner_company_condition.partner_company_id, private.current_user_id())
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.update_invoice_partner_company_condition (
    id                          uuid,
    partner_company_id_equality rule.equality_operator,
    partner_company_id          uuid = NULL
) RETURNS rule.invoice_partner_company_condition AS
$$
    UPDATE rule.invoice_partner_company_condition
        SET
            partner_company_id_equality=update_invoice_partner_company_condition.partner_company_id_equality,
            partner_company_id=update_invoice_partner_company_condition.partner_company_id,
            updated_by=private.current_user_id(),
            updated_at=now()
    WHERE id = update_invoice_partner_company_condition.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.delete_invoice_partner_company_condition (
    id uuid
) RETURNS rule.invoice_partner_company_condition AS
$$
    DELETE FROM rule.invoice_partner_company_condition
    WHERE id = delete_invoice_partner_company_condition.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;
