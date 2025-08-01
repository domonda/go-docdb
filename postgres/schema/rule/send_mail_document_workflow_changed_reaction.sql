-- TODO-db-210824 use private.notification instead

create table rule.send_mail_document_workflow_changed_reaction(
    reaction_id uuid primary key references rule.reaction(id) on delete cascade,

    user_id uuid not null references public.user(id) on delete cascade,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time not null,
    created_at created_time not null
);

grant all on rule.send_mail_document_workflow_changed_reaction to domonda_user;
grant select on rule.send_mail_document_workflow_changed_reaction to domonda_wg_user;

----

create function rule.check_send_mail_document_workflow_changed_reaction_is_used()
returns trigger as $$
declare
    rec rule.send_mail_document_workflow_changed_reaction;
begin
    if TG_OP = 'DELETE' then
        rec = OLD;
    else
        rec = NEW;
    end if;

    if exists (select from rule.action_reaction where action_reaction.reaction_id = rec.reaction_id)
        and not rule.current_user_is_special()
    then
        raise exception 'Reaction is in use';
    end if;

    return rec;
end
$$ language plpgsql stable;

create trigger rule_check_send_mail_document_workflow_changed_reaction_is_used_trigger
    before insert or update or delete
    on rule.send_mail_document_workflow_changed_reaction
    for each row
    execute procedure rule.check_send_mail_document_workflow_changed_reaction_is_used();

----

create function rule.create_send_mail_document_workflow_changed_reaction(
    reaction_id uuid,
    user_id     uuid
) returns rule.send_mail_document_workflow_changed_reaction as
$$
    insert into rule.send_mail_document_workflow_changed_reaction (reaction_id, user_id, created_by)
    values (
        create_send_mail_document_workflow_changed_reaction.reaction_id,
        create_send_mail_document_workflow_changed_reaction.user_id,
        private.current_user_id()
    )
    returning *
$$
language sql volatile strict;

----

create function rule.update_send_mail_document_workflow_changed_reaction(
    reaction_id uuid,
    user_id     uuid
) returns rule.send_mail_document_workflow_changed_reaction as
$$
    update rule.send_mail_document_workflow_changed_reaction
    set
        user_id=update_send_mail_document_workflow_changed_reaction.user_id,
        updated_by=private.current_user_id(),
        updated_at=now()
    where reaction_id = update_send_mail_document_workflow_changed_reaction.reaction_id
    returning *
$$
language sql volatile strict;

----

create function rule.delete_send_mail_document_workflow_changed_reaction(
    reaction_id uuid
) returns rule.send_mail_document_workflow_changed_reaction as
$$
    delete from rule.send_mail_document_workflow_changed_reaction
    where reaction_id = delete_send_mail_document_workflow_changed_reaction.reaction_id
    returning *
$$
language sql volatile strict;

----

CREATE FUNCTION rule.do_send_mail_document_workflow_changed_reaction(
    send_mail_document_workflow_changed_reaction rule.send_mail_document_workflow_changed_reaction,
    document public.document
) RETURNS worker.job AS
$$
DECLARE
    receiving_user    record;
    job_payload       jsonb;
    debouncable_job   record;
    debounce_timeout  interval := interval '10 mins';
BEGIN
    -- find receiving user
    SELECT
        * INTO receiving_user
    FROM public.user
    WHERE id = send_mail_document_workflow_changed_reaction.user_id;

    -- find debouncable job
        -- job type is 'SEND_MAIL'
        -- the receiver is the same
        -- job payload `templateType` is 'DOCUMENT_WORKFLOWS_CHANGED'
        -- `start_at` exists
    SELECT
        * INTO debouncable_job
    FROM worker.job
    WHERE (
        "type" = 'SEND_MAIL'
    ) AND (
        payload->>'to' = receiving_user.email
    ) AND (
        payload->>'templateType' = 'DOCUMENT_WORKFLOWS_CHANGED'
    ) AND (
        (start_at IS NOT NULL)
    ) AND (
        started_at is null
    )
    FOR UPDATE;

    -- prepare job payload
    job_payload := jsonb_build_object(
        'to', receiving_user.email,
        'templateType', 'DOCUMENT_WORKFLOWS_CHANGED',
        'templateLang', UPPER(receiving_user."language"),
        'templateData', jsonb_build_object(
            'UserName', receiving_user.first_name,
            'Documents', (
                jsonb_agg(
                    jsonb_build_object(
                        'ID', document.id,
                        'CompanyName', (SELECT public.company_brand_name_or_name(company) FROM public.company WHERE id = document.client_company_id),
                        'WorkflowName', COALESCE(
                            (SELECT public.document_workflow_step_full_name(document_workflow_step) FROM public.document_workflow_step WHERE id = document.workflow_step_id),
                            '—'
                        )
                    )
                )
            )
        )
    );

    IF debouncable_job IS NULL THEN
        -- there is NO debouncable job, create one

        INSERT INTO worker.job (
            "type",
            payload,
            priority,
            origin,
            max_retry_count,
            start_at
        )
        VALUES (
            'SEND_MAIL',
            job_payload,
            0,
            'rule.do_send_mail_document_workflow_changed_reaction()',
            3,
            (now() + debounce_timeout)
        )
        RETURNING
            * INTO debouncable_job;

    ELSE
        -- there is a debouncable job, concatanate payload `Documents` if the document doesn't exist and debounce it

        if exists(
            select from jsonb_array_elements(debouncable_job.payload#>'{templateData,Documents}') as el
            where el->>'ID' = document.id::text
        ) then
            -- document is already queued in the mail
            return null;
        end if;

        job_payload := jsonb_set(
            job_payload,
            '{templateData,Documents}',
            (debouncable_job.payload#>'{templateData,Documents}') || (job_payload#>'{templateData,Documents}')
        );

        UPDATE worker.job
        SET
            payload=job_payload,
            start_at=(now() + debounce_timeout),
            updated_at=now()
        WHERE id = debouncable_job.id
        RETURNING
            * INTO debouncable_job;

    END IF;

    RETURN debouncable_job;
END
$$
LANGUAGE plpgsql VOLATILE STRICT SECURITY DEFINER;

COMMENT ON FUNCTION rule.do_send_mail_document_workflow_changed_reaction IS '@omit';

----

create function rule.do_send_mail_document_workflow_changed_action_reaction(
    action_reaction rule.action_reaction,
    document        public.document
) returns void as
$$
declare
    send_mail_document_workflow_changed_reaction rule.send_mail_document_workflow_changed_reaction;
begin
    if action_reaction."trigger" in ('ALWAYS', 'ONCE', 'DOCUMENT_CHANGED')
        and exists(
            select from rule.send_mail_document_workflow_changed_log
            where send_mail_document_workflow_changed_log.action_reaction_id = action_reaction.id
                and send_mail_document_workflow_changed_log.document_id = document.id
                and (action_reaction."trigger" = 'ONCE'
                    -- some triggers should not execute multiple times recursively
                    or send_mail_document_workflow_changed_log.created_at = now()
                )
        )
    then
        return;
    end if;

    -- find reaction
    select * into send_mail_document_workflow_changed_reaction from rule.send_mail_document_workflow_changed_reaction where reaction_id = action_reaction.reaction_id;

    -- if there is no reaction, return
    if send_mail_document_workflow_changed_reaction is null then
        return;
    end if;

    -- disabled or email-less users cannot be notified
    if (
        select not "user".enabled or "user".email is null
        from public.user
        where "user".id = send_mail_document_workflow_changed_reaction.user_id
    ) then
        return;
    end if;

    -- react
    perform rule.do_send_mail_document_workflow_changed_reaction(send_mail_document_workflow_changed_reaction, document);

    -- log
    insert into rule.send_mail_document_workflow_changed_log (action_reaction_id, document_id)
    values (action_reaction.id, document.id);
end
$$
language plpgsql volatile;

comment on function rule.do_send_mail_document_workflow_changed_action_reaction is '@omit';
