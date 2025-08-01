CREATE TABLE rule.document_category_document_type_condition (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),

    action_id uuid NOT NULL REFERENCES rule.action(id) ON DELETE CASCADE,

    document_type_equality rule.equality_operator NOT NULL,
    document_type          public.document_type,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    created_at created_time NOT NULL,
    updated_at updated_time NOT NULL
);

GRANT ALL ON rule.document_category_document_type_condition TO domonda_user;
grant select on rule.document_category_document_type_condition to domonda_wg_user;

CREATE UNIQUE INDEX rule_document_category_document_type_condition_unique ON rule.document_category_document_type_condition (action_id, document_type);
CREATE UNIQUE INDEX rule_document_category_document_type_condition_unique_null ON rule.document_category_document_type_condition (action_id) WHERE (document_type IS NULL);

CREATE INDEX rule_document_category_document_type_condition_action_id_idx ON rule.document_category_document_type_condition (action_id);

----

create function rule.check_document_category_document_type_condition_is_used()
returns trigger as $$
declare
    rec rule.document_category_document_type_condition;
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

create trigger rule_check_document_category_document_type_condition_is_used_trigger
    before insert or update or delete
    on rule.document_category_document_type_condition
    for each row
    execute procedure rule.check_document_category_document_type_condition_is_used();

----

CREATE FUNCTION rule.create_document_category_document_type_condition (
    action_id              uuid,
    document_type_equality rule.equality_operator,
    document_type          public.document_type = NULL
) RETURNS rule.document_category_document_type_condition AS
$$
    INSERT INTO rule.document_category_document_type_condition (action_id, document_type_equality, document_type, created_by)
        VALUES (create_document_category_document_type_condition.action_id, create_document_category_document_type_condition.document_type_equality, create_document_category_document_type_condition.document_type, private.current_user_id())
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.update_document_category_document_type_condition (
    id                     uuid,
    document_type_equality rule.equality_operator,
    document_type          public.document_type = NULL
) RETURNS rule.document_category_document_type_condition AS
$$
    UPDATE rule.document_category_document_type_condition
        SET
            document_type_equality=update_document_category_document_type_condition.document_type_equality,
            document_type=update_document_category_document_type_condition.document_type,
            updated_by=private.current_user_id(),
            updated_at=now()
    WHERE id = update_document_category_document_type_condition.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.delete_document_category_document_type_condition (
    id uuid
) RETURNS rule.document_category_document_type_condition AS
$$
    DELETE FROM rule.document_category_document_type_condition
    WHERE id = delete_document_category_document_type_condition.id
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;
