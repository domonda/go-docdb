CREATE TABLE rule.document_reaction (
    reaction_id uuid PRIMARY KEY REFERENCES rule.reaction(id) ON DELETE CASCADE,

    change_workflow_step_id boolean NOT NULL DEFAULT false,
    workflow_step_id        uuid REFERENCES public.document_workflow_step(id) ON DELETE CASCADE,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT ALL ON rule.document_reaction TO domonda_user;
grant select on rule.document_reaction to domonda_wg_user;

----

create function rule.check_document_reaction_is_used()
returns trigger as $$
declare
    rec rule.document_reaction;
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

create trigger rule_check_document_reaction_is_used_trigger
    before insert or update or delete
    on rule.document_reaction
    for each row
    execute procedure rule.check_document_reaction_is_used();

----

CREATE FUNCTION rule.create_document_reaction(
    reaction_id             uuid,
    change_workflow_step_id boolean,
    workflow_step_id        uuid = NULL
) RETURNS rule.document_reaction AS
$$
    INSERT INTO rule.document_reaction (
        reaction_id,
        change_workflow_step_id,
        workflow_step_id,
        created_by
    ) VALUES (
        create_document_reaction.reaction_id,
        create_document_reaction.change_workflow_step_id,
        create_document_reaction.workflow_step_id,
        private.current_user_id()
    )
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.update_document_reaction(
    reaction_id             uuid,
    change_workflow_step_id boolean,
    workflow_step_id        uuid = NULL
) RETURNS rule.document_reaction AS
$$
    UPDATE rule.document_reaction
        SET
            change_workflow_step_id=update_document_reaction.change_workflow_step_id,
            workflow_step_id=update_document_reaction.workflow_step_id,
            updated_by=private.current_user_id(),
            updated_at=now()
    WHERE reaction_id = update_document_reaction.reaction_id
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.delete_document_reaction(
    reaction_id uuid
) RETURNS rule.document_reaction AS
$$
    DELETE FROM rule.document_reaction
    WHERE reaction_id = delete_document_reaction.reaction_id
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;

----

CREATE FUNCTION rule.do_document_reaction(
    document_reaction rule.document_reaction,
    document          public.document
) RETURNS public.document AS
$$
BEGIN

    IF document_reaction.change_workflow_step_id = true THEN
        document.workflow_step_id = document_reaction.workflow_step_id;
    END IF;

    RETURN document;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

COMMENT ON FUNCTION rule.do_document_reaction IS '@omit';

----

CREATE FUNCTION rule.do_document_action_reaction(
    action_reaction rule.action_reaction,
    document        public.document
) RETURNS public.document AS
$$
DECLARE
    document_reaction rule.document_reaction;
    -- document workflow step log
    prev_document_workflow_step_id uuid := document.workflow_step_id;
BEGIN
    if action_reaction."trigger" in ('ALWAYS', 'ONCE', 'DOCUMENT_CHANGED')
    and exists(select from rule.document_log
        where document_log.action_reaction_id = action_reaction.id
        and document_log.document_id = document.id
        and (action_reaction."trigger" = 'ONCE'
            -- some triggers should not execute multiple times recursively
            or document_log.created_at = now())
        )
    then
        return document;
    end if;

    -- find reaction
    SELECT * INTO document_reaction FROM rule.document_reaction WHERE reaction_id = action_reaction.reaction_id;

    -- if there is no reaction, return
    IF document_reaction IS NULL OR document.superseded THEN
        RETURN document;
    END IF;

    -- react
    document = rule.do_document_reaction(document_reaction, document);

    -- log
    INSERT INTO rule.document_log (action_reaction_id, document_id)
        VALUES (action_reaction.id, document.id);

    RETURN document;
END
$$
LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION rule.do_document_action_reaction IS '@omit';
