CREATE TABLE rule.invoice_total_condition (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    action_id uuid NOT NULL REFERENCES rule.action(id) ON DELETE CASCADE,

    total_comparison rule.comparison_operator NOT NULL,
    total            float8,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT ALL ON rule.invoice_total_condition TO domonda_user;
grant select on rule.invoice_total_condition to domonda_wg_user;

CREATE UNIQUE INDEX rule_invoice_total_condition_unique ON rule.invoice_total_condition (action_id, total);
CREATE UNIQUE INDEX rule_invoice_total_condition_unique_null ON rule.invoice_total_condition (action_id) WHERE (total IS NULL);

CREATE INDEX rule_invoice_total_condition_action_id_idx ON rule.invoice_total_condition (action_id);

----

create function rule.check_invoice_total_condition_is_used()
returns trigger as $$
declare
    rec rule.invoice_total_condition;
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

create trigger rule_check_invoice_total_condition_is_used_trigger
    before insert or update or delete
    on rule.invoice_total_condition
    for each row
    execute procedure rule.check_invoice_total_condition_is_used();

----

CREATE FUNCTION rule.create_invoice_total_condition (
    action_id        uuid,
    total_comparison rule.comparison_operator,
    total            float8 = NULL
) RETURNS rule.invoice_total_condition AS
$$
    INSERT INTO rule.invoice_total_condition (action_id, total_comparison, total, created_by)
        VALUES (create_invoice_total_condition.action_id, create_invoice_total_condition.total_comparison, create_invoice_total_condition.total, private.current_user_id())
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.update_invoice_total_condition (
    id               uuid,
    total_comparison rule.comparison_operator,
    total            float8 = NULL
) RETURNS rule.invoice_total_condition AS
$$
    UPDATE rule.invoice_total_condition
        SET
            total_comparison=update_invoice_total_condition.total_comparison,
            total=update_invoice_total_condition.total,
            updated_by=private.current_user_id(),
            updated_at=now()
    WHERE id = update_invoice_total_condition.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.delete_invoice_total_condition (
    id uuid
) RETURNS rule.invoice_total_condition AS
$$
    DELETE FROM rule.invoice_total_condition
    WHERE id = delete_invoice_total_condition.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;
