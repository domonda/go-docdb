create table rule.document_approval_request_reaction (
    reaction_id uuid primary key references rule.reaction(id) on delete cascade,

    blank_approver_count int check(blank_approver_count > 0),
    blank_approver_type  public.document_approval_request_blank_approver_type,

    approver_id   uuid references public.user(id) on delete cascade,
    user_group_id uuid references public.user_group(id) on delete set null,
    controller_user_from_document_partner_company boolean not null default false,

    constraint only_one_approver_type_allowed check(
        case
            when approver_id is not null
            then user_group_id is null
                and blank_approver_type is null
                and not controller_user_from_document_partner_company
            when user_group_id is not null
            then approver_id is null
                and blank_approver_type is null
                and not controller_user_from_document_partner_company
            when blank_approver_type is not null
            then approver_id is null
                and user_group_id is null
                and not controller_user_from_document_partner_company
            when controller_user_from_document_partner_company
            then approver_id is null
                and user_group_id is null
                and blank_approver_type is null
            else false
        end
    ),

    -- having a blank_approver_count requires a blank_approver_type
    constraint black_approver_count_needs_type check((blank_approver_count is null) or (blank_approver_type is not null)),

    message text check(length(message) > 0),

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- SYSTEM Unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- TODO-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time not null,
    created_at created_time not null
);

grant all on rule.document_approval_request_reaction to domonda_user;
grant select on rule.document_approval_request_reaction to domonda_wg_user;

----

create function rule.check_document_approval_request_reaction_is_used()
returns trigger as $$
declare
    rec rule.document_approval_request_reaction;
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

create trigger rule_check_document_approval_request_reaction_is_used_trigger
    before insert or update or delete
    on rule.document_approval_request_reaction
    for each row
    execute procedure rule.check_document_approval_request_reaction_is_used();

----

create function rule.create_document_approval_request(
    reaction_id          uuid,
    controller_user_from_document_partner_company boolean = false,
    blank_approver_count int = null,
    blank_approver_type  public.document_approval_request_blank_approver_type = null,
    user_group_id        uuid = null,
    approver_id          uuid = null,
    message              text = null
) returns rule.document_approval_request_reaction as
$$
    insert into rule.document_approval_request_reaction (
        reaction_id,
        controller_user_from_document_partner_company,
        blank_approver_count,
        blank_approver_type,
        user_group_id,
        approver_id,
        message,
        created_by
    ) values (
        create_document_approval_request.reaction_id,
        create_document_approval_request.controller_user_from_document_partner_company,
        create_document_approval_request.blank_approver_count,
        create_document_approval_request.blank_approver_type,
        create_document_approval_request.user_group_id,
        create_document_approval_request.approver_id,
        create_document_approval_request.message,
        private.current_user_id()
    )
    returning *
$$
language sql volatile;

----

create function rule.update_document_approval_request(
    reaction_id          uuid,
    controller_user_from_document_partner_company boolean = false,
    blank_approver_count int = null,
    blank_approver_type  public.document_approval_request_blank_approver_type = null,
    user_group_id        uuid = null,
    approver_id          uuid = null,
    message              text = null
) returns rule.document_approval_request_reaction as
$$
    update rule.document_approval_request_reaction
    set
        controller_user_from_document_partner_company=update_document_approval_request.controller_user_from_document_partner_company,
        blank_approver_count=update_document_approval_request.blank_approver_count,
        blank_approver_type=update_document_approval_request.blank_approver_type,
        user_group_id=update_document_approval_request.user_group_id,
        approver_id=update_document_approval_request.approver_id,
        message=update_document_approval_request.message,
        updated_by=private.current_user_id(),
        updated_at=now()
    where reaction_id = update_document_approval_request.reaction_id
    returning *
$$
language sql volatile;

----

create function rule.delete_document_approval_request(
    reaction_id uuid
) returns rule.document_approval_request_reaction as
$$
    delete from rule.document_approval_request_reaction
    where reaction_id = delete_document_approval_request.reaction_id
    returning *
$$
language sql volatile strict;

----

-- returns void because it the reaction can insert 1 or more rows
create function rule.do_document_approval_request_reaction(
    document_approval_request_reaction rule.document_approval_request_reaction,
    document                           public.document
) returns void as
$$
declare
    approver_id uuid;
    approver_group_id uuid;
begin
    if document_approval_request_reaction.controller_user_from_document_partner_company then
        select
            partner_company.user_id,
            partner_company.user_group_id
        into
            approver_id,
            approver_group_id
        from public.partner_company
            left join public.invoice on invoice.document_id = document.id
            left join public.other_document on other_document.document_id = document.id
        where partner_company.id = coalesce(invoice.partner_company_id, other_document.partner_company_id);
        if approver_id is null and approver_group_id is null then
            raise exception 'Document''s partner doesn''t have a controller for approvals';
        end if;
    elsif document_approval_request_reaction.approver_id is not null then
        approver_id = document_approval_request_reaction.approver_id;
    elsif document_approval_request_reaction.user_group_id is not null then
        approver_group_id = document_approval_request_reaction.user_group_id;
    end if;

    if approver_id is not null then
        -- duplicate direct approval requests are disallowed
        -- if there is already one open, cancel it.
        -- we need to disable the rule trigger to avoid recursive rule trigger invokations
        set local current.disable_rule_trigger to true;
        insert into public.document_approval (request_id, approver_id, canceled)
        select
            document_approval_request.id,
            'bde919f0-3e23-4bfa-81f1-abff4f45fb51', -- Rule system user
            true
        from public.document_approval_request
        where document_approval_request.document_id = document.id
            and document_approval_request.approver_id = document_approval_request_reaction.approver_id
            -- is open
            and not exists (
                select from public.document_approval
                where document_approval.request_id = document_approval_request.id
            )
            -- not a rejection
            and not exists (
                select from public.document_approval
                where document_approval.next_request_id = document_approval_request.id
            );
        reset current.disable_rule_trigger;

        insert into public.document_approval_request (document_id, requester_id, approver_id, message)
        values (
            document.id,
            'bde919f0-3e23-4bfa-81f1-abff4f45fb51', -- Rule system user
            approver_id,
            document_approval_request_reaction.message
        );
        return;
    end if;

    if approver_group_id is not null then
        insert into public.document_approval_request (document_id, requester_id, user_group_id, message)
        values (
            document.id,
            'bde919f0-3e23-4bfa-81f1-abff4f45fb51', -- Rule system user
            approver_group_id,
            document_approval_request_reaction.message
        );
        return;
    end if;

    for _ in 1..document_approval_request_reaction.blank_approver_count loop
        insert into public.document_approval_request (document_id, requester_id, blank_approver_type, message)
        values (
            document.id,
            'bde919f0-3e23-4bfa-81f1-abff4f45fb51', -- Rule system user
            document_approval_request_reaction.blank_approver_type,
            document_approval_request_reaction.message
        );
    end loop;
end
$$
language plpgsql volatile strict;

comment on function rule.do_document_approval_request_reaction is '@omit';

----

create function rule.do_document_approval_request_action_reaction(
    action_reaction rule.action_reaction,
    document        public.document
) returns void as
$$
declare
    document_approval_request_reaction rule.document_approval_request_reaction;
begin
    if action_reaction."trigger" in ('ALWAYS', 'ONCE', 'DOCUMENT_CHANGED')
        and exists(
            select from rule.document_approval_request_log
            where document_approval_request_log.action_reaction_id = action_reaction.id
                and document_approval_request_log.document_id = document.id
                and (action_reaction."trigger" = 'ONCE'
                    -- some triggers should not execute multiple times recursively
                    or document_approval_request_log.created_at = now()
                )
        )
    then
        return;
    end if;

    -- find reaction
    select
        * into document_approval_request_reaction
    from rule.document_approval_request_reaction where reaction_id = action_reaction.reaction_id;

    -- if there is no reaction, return
    if document_approval_request_reaction is null then
        return;
    end if;

    -- react
    perform rule.do_document_approval_request_reaction(document_approval_request_reaction, document);

    -- log
    insert into rule.document_approval_request_log (action_reaction_id, document_id)
    values (action_reaction.id, document.id);
end
$$
language plpgsql volatile;

comment on function rule.do_document_approval_request_action_reaction is '@omit';
