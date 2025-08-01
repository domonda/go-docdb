-- no primary key because there can be only one invoice_condition
CREATE TABLE rule.invoice_condition (
    action_id uuid PRIMARY KEY REFERENCES rule.action(id) ON DELETE CASCADE,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,

    created_at created_time NOT NULL
);

GRANT ALL ON rule.invoice_condition TO domonda_user;
grant select on rule.invoice_condition to domonda_wg_user;

CREATE INDEX rule_invoice_condition_action_id_idx ON rule.invoice_condition (action_id);

----

create function rule.check_invoice_condition_is_used()
returns trigger as $$
declare
    rec rule.invoice_condition;
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

create trigger rule_check_invoice_condition_is_used_trigger
    before insert or update or delete
    on rule.invoice_condition
    for each row
    execute procedure rule.check_invoice_condition_is_used();

----

CREATE FUNCTION rule.create_invoice_condition (
    action_id uuid
) RETURNS rule.invoice_condition AS
$$
    INSERT INTO rule.invoice_condition (action_id, created_by)
        VALUES (create_invoice_condition.action_id, private.current_user_id())
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;

----

CREATE FUNCTION rule.delete_invoice_condition (
    action_id uuid
) RETURNS rule.invoice_condition AS
$$
    DELETE FROM rule.invoice_condition
    WHERE action_id = delete_invoice_condition.action_id
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;
