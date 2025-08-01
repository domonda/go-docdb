create table rule.send_notification_reaction(
    reaction_id uuid primary key references rule.reaction(id) on delete cascade,

    destination public.notification_destination not null,

    receiver_user_id uuid references public.user(id) on delete cascade,
    receiver_email   public.email_addr,
    receiver_url     text, -- TODO-db-211021 create url domain
    constraint only_one_receiver_address check(
        (receiver_user_id is not null
        and (receiver_email is null and receiver_url is null))
        or (receiver_email is not null
        and (receiver_user_id is null and receiver_url is null))
        or (receiver_url is not null
        and (receiver_user_id is null and receiver_email is null))
    ),

    token non_empty_text,

    note non_empty_text,

    created_by uuid not null
        default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system unknown
        references public.user(id) on delete set default,
    updated_by uuid references public.user(id) on delete set null, -- todo-db-210715 if the user that did the update gets deleted, this column will be `null`

    updated_at updated_time not null,
    created_at created_time not null
);

grant all on rule.send_notification_reaction to domonda_user;
grant select on rule.send_notification_reaction to domonda_wg_user;

----

create function rule.check_send_notification_reaction_is_used()
returns trigger as $$
declare
    rec rule.send_notification_reaction;
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

create trigger rule_check_send_notification_reaction_is_used_trigger
    before insert or update or delete
    on rule.send_notification_reaction
    for each row
    execute procedure rule.check_send_notification_reaction_is_used();

----

create function rule.create_send_notification_reaction(
    reaction_id      uuid,
    destination      public.notification_destination,
    receiver_user_id uuid = null,
    receiver_email   public.email_addr = null,
    receiver_url     text = null,
    token            non_empty_text = null,
    note             non_empty_text = null
) returns rule.send_notification_reaction as
$$
    insert into rule.send_notification_reaction (
        reaction_id,
        destination,
        receiver_user_id,
        receiver_email,
        receiver_url,
        token,
        note,
        created_by
    ) values (
        create_send_notification_reaction.reaction_id,
        create_send_notification_reaction.destination,
        create_send_notification_reaction.receiver_user_id,
        create_send_notification_reaction.receiver_email,
        create_send_notification_reaction.receiver_url,
        create_send_notification_reaction.token,
        create_send_notification_reaction.note,
        private.current_user_id()
    ) returning *
$$
language sql volatile;

create function rule.update_send_notification_reaction(
    reaction_id      uuid,
    destination      public.notification_destination,
    receiver_user_id uuid = null,
    receiver_email   public.email_addr = null,
    receiver_url     text = null,
    token            non_empty_text = null,
    note             non_empty_text = null
) returns rule.send_notification_reaction as
$$
    update rule.send_notification_reaction
        set
            destination=update_send_notification_reaction.destination,
            receiver_user_id=update_send_notification_reaction.receiver_user_id,
            receiver_email=update_send_notification_reaction.receiver_email,
            receiver_url=update_send_notification_reaction.receiver_url,
            token=update_send_notification_reaction.token,
            note=update_send_notification_reaction.note,
            updated_by=private.current_user_id(),
            updated_at=now()
    where reaction_id = update_send_notification_reaction.reaction_id
    returning *
$$
language sql volatile;

create function rule.delete_send_notification_reaction(
    reaction_id uuid
) returns rule.send_notification_reaction as
$$
    delete from rule.send_notification_reaction
    where reaction_id = delete_send_notification_reaction.reaction_id
    returning *
$$
language sql volatile strict;

----

create function rule.do_send_notification_action_reaction(
    action_reaction rule.action_reaction,
    document        public.document
) returns void as $$
declare
    reaction rule.send_notification_reaction;
    notif    private.notification;
begin
    if action_reaction."trigger" in ('ALWAYS', 'ONCE', 'DOCUMENT_CHANGED')
    and exists(select from rule.send_notification_log
        where send_notification_log.action_reaction_id = action_reaction.id
        and send_notification_log.document_id = document.id
        and (action_reaction."trigger" = 'ONCE'
            -- some triggers should not execute multiple times recursively
            or send_notification_log.created_at = now())
        )
    then
        return;
    end if;

    select * into reaction from rule.send_notification_reaction
    where reaction_id = action_reaction.reaction_id;

    -- if there is no reaction, just return
    if reaction is null then
        return;
    end if;

    -- disabled or email-less users cannot be notified
    if (
        select not "user".enabled or "user".email is null
        from public.user
        where "user".id = reaction.receiver_user_id
    ) then
        return;
    end if;

    notif := private.notify_document_info(
        destination=>reaction.destination,
        document=>do_send_notification_action_reaction.document,
        note=>reaction.note,
        receiver_user_id=>reaction.receiver_user_id,
        receiver_email=>reaction.receiver_email,
        receiver_url=>reaction.receiver_url,
        action_reaction_id=>action_reaction.id
    );

    insert into rule.send_notification_log (action_reaction_id, document_id, notification_id)
        values (action_reaction.id, document.id, notif.id);
end
$$
language plpgsql volatile
security definer; -- for creating logs
comment on function rule.do_send_notification_action_reaction is '@omit';
