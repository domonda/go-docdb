CREATE TABLE rule.cancel_document_approval_request_reaction (
    reaction_id uuid PRIMARY KEY REFERENCES rule.reaction(id) ON DELETE CASCADE,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,

    updated_at updated_time NOT NULL,
    created_at created_time NOT NULL
);

GRANT ALL ON rule.cancel_document_approval_request_reaction TO domonda_user;
grant select on rule.cancel_document_approval_request_reaction to domonda_wg_user;

----

create function rule.check_cancel_document_approval_request_reaction_is_used()
returns trigger as $$
declare
    rec rule.cancel_document_approval_request_reaction;
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

create trigger rule_check_cancel_document_approval_request_reaction_is_used_trigger
    before insert or update or delete
    on rule.cancel_document_approval_request_reaction
    for each row
    execute procedure rule.check_cancel_document_approval_request_reaction_is_used();

----

CREATE FUNCTION rule.create_cancel_document_approval_request_reaction(
    reaction_id uuid
) RETURNS rule.cancel_document_approval_request_reaction AS
$$
    INSERT INTO rule.cancel_document_approval_request_reaction (
        reaction_id,
        created_by
    ) VALUES (
        create_cancel_document_approval_request_reaction.reaction_id,
        private.current_user_id()
    )
    RETURNING *
$$
LANGUAGE SQL VOLATILE;

----

CREATE FUNCTION rule.delete_cancel_document_approval_request_reaction(
    reaction_id uuid
) RETURNS rule.cancel_document_approval_request_reaction AS
$$
    DELETE FROM rule.cancel_document_approval_request_reaction
    WHERE reaction_id = delete_cancel_document_approval_request_reaction.reaction_id
    RETURNING *
$$
LANGUAGE SQL VOLATILE STRICT;

----

CREATE FUNCTION rule.do_cancel_document_approval_request_reaction(
    cancel_document_approval_request_reaction rule.cancel_document_approval_request_reaction,
    document          public.document
) RETURNS public.document AS
$$
BEGIN

    -- cancel all non-VERIFIER open approval requests
    insert into public.document_approval (request_id, approver_id, canceled)
    select
        id,
        'bde919f0-3e23-4bfa-81f1-abff4f45fb51', -- Rule
        true
    from public.document_approval_request
    where document_approval_request.document_id = document.id
    and public.document_approval_request_open(document_approval_request)
    and blank_approver_type is distinct from 'VERIFIER';

    RETURN document;
END
$$
LANGUAGE plpgsql VOLATILE STRICT;

COMMENT ON FUNCTION rule.do_cancel_document_approval_request_reaction IS '@omit';

----

CREATE FUNCTION rule.do_cancel_document_approval_request_action_reaction(
    action_reaction rule.action_reaction,
    document        public.document
) RETURNS public.document AS
$$
DECLARE
    cancel_document_approval_request_reaction rule.cancel_document_approval_request_reaction;
    -- document workflow step log
    prev_document_workflow_step_id uuid := document.workflow_step_id;
BEGIN
    if action_reaction."trigger" in ('ALWAYS', 'ONCE', 'DOCUMENT_CHANGED')
    and exists(select from rule.cancel_document_approval_request_log
        where cancel_document_approval_request_log.action_reaction_id = action_reaction.id
        and cancel_document_approval_request_log.document_id = document.id
        and (action_reaction."trigger" = 'ONCE'
            -- some triggers should not execute multiple times recursively
            or cancel_document_approval_request_log.created_at = now())
        )
    then
        return document;
    end if;

    -- find reaction
    SELECT * INTO cancel_document_approval_request_reaction FROM rule.cancel_document_approval_request_reaction WHERE reaction_id = action_reaction.reaction_id;

    -- if there is no reaction, return
    IF cancel_document_approval_request_reaction IS NULL THEN
        RETURN document;
    END IF;

    -- if there are no open approval requests, return
    if not exists (select from public.document_approval_request
        where document_approval_request.document_id = document.id
        and public.document_approval_request_open(document_approval_request)
        and blank_approver_type is distinct from 'VERIFIER')
    then
        return document;
    end if;

    -- react
    perform rule.do_cancel_document_approval_request_reaction(cancel_document_approval_request_reaction, document);

    -- log
    INSERT INTO rule.cancel_document_approval_request_log (action_reaction_id, document_id)
        VALUES (action_reaction.id, document.id);

    RETURN document;
END
$$
LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION rule.do_cancel_document_approval_request_action_reaction IS '@omit';
