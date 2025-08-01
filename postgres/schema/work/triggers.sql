-------------------------------------------------------------------------------
-- work.group triggers

create function work.group_created() returns trigger
language plpgsql as
$$
begin
    insert into work.group_log (group_id, "type", created_by, created_at)
        values (new.id, 'GROUP_CREATED', new.created_by, new.created_at);
    return new;
end
$$;

create trigger group_created
    after insert on work.group
    for each row
    execute procedure work.group_created();

----

create function work.group_disabled() returns trigger
language plpgsql as
$$
begin
    insert into work.group_log (group_id, "type", created_by, created_at)
        values (new.id, 'GROUP_DISABLED', new.disabled_by, new.disabled_at);
    return new;
end
$$;

create trigger group_disabled
    after update on work.group
    for each row
    when (old.disabled_at is null and new.disabled_at is not null)
    execute procedure work.group_disabled();

-------------------------------------------------------------------------------
-- work.group_chat triggers

create function work.group_chat_mentioned_user() returns trigger
language plpgsql as
$$
begin
    perform pg_notify('work_group_chat_mentioned_user', new.id::text);
    return new;
end
$$;

create trigger group_chat_mentioned_user
    after insert on work.group_chat
    for each row
    when (array_length(work.group_chat_message_mentioned_user_ids(new), 1) > 0)
    execute procedure work.group_chat_mentioned_user();