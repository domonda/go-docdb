CREATE TABLE rule.invoice_completeness_level_condition (
    id uuid primary key default uuid_generate_v4(),

    action_id uuid not null REFERENCES rule.action(id) ON DELETE CASCADE,

    completeness_level_equality rule.equality_operator NOT NULL,
    completeness_level          public.invoice_completeness_level NOT NULL,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT ALL ON rule.invoice_completeness_level_condition TO domonda_user;
grant select on rule.invoice_completeness_level_condition to domonda_wg_user;

----

create function rule.check_invoice_completeness_level_condition_is_used()
returns trigger as $$
declare
    rec rule.invoice_completeness_level_condition;
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

create trigger rule_check_invoice_completeness_level_condition_is_used_trigger
    before insert or update or delete
    on rule.invoice_completeness_level_condition
    for each row
    execute procedure rule.check_invoice_completeness_level_condition_is_used();

----

CREATE FUNCTION rule.create_invoice_completeness_level_condition (
    action_id                   uuid,
    completeness_level_equality rule.equality_operator,
    completeness_level          public.invoice_completeness_level
) RETURNS rule.invoice_completeness_level_condition AS
$$
    INSERT INTO rule.invoice_completeness_level_condition (action_id, completeness_level_equality, completeness_level, created_by)
        VALUES (create_invoice_completeness_level_condition.action_id, create_invoice_completeness_level_condition.completeness_level_equality, create_invoice_completeness_level_condition.completeness_level, private.current_user_id())
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;

----

CREATE FUNCTION rule.update_invoice_completeness_level_condition (
    id                          uuid,
    completeness_level_equality rule.equality_operator,
    completeness_level          public.invoice_completeness_level
) RETURNS rule.invoice_completeness_level_condition AS
$$
    UPDATE rule.invoice_completeness_level_condition
        SET
            completeness_level_equality=update_invoice_completeness_level_condition.completeness_level_equality,
            completeness_level=update_invoice_completeness_level_condition.completeness_level,
            updated_by=private.current_user_id(),
            updated_at=now()
    WHERE id = update_invoice_completeness_level_condition.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.delete_invoice_completeness_level_condition (
    id uuid
) RETURNS rule.invoice_completeness_level_condition AS
$$
    DELETE FROM rule.invoice_completeness_level_condition
    WHERE id = delete_invoice_completeness_level_condition.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;
