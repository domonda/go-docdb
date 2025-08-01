create table work.group_chat (
    id uuid primary key default uuid_generate_v4(),

    group_id uuid not null references work.group(id) on delete cascade,
    reply_to uuid references work.group_chat(id) on delete set null,
    message jsonb not null,

    -- References public.user instead of work.group_user
    -- because a work.group_user can be removed from a group
    -- in which case the message should still stay in the group.
    -- Might also be a system user.
    created_by uuid not null references public.user(id) on delete restrict,
    created_at timestamptz not null default now()
);

create index group_chat_group_id_idx on work.group_chat(group_id);
create index group_chat_reply_to_idx on work.group_chat(reply_to);

----

create function work.validate_group_chat_message(message jsonb) returns text
language plpgsql as
$$
declare
    elem jsonb;
    k    text;
    v    jsonb;
begin
    if message is null then
        return 'message is NULL';
    end if;

    if jsonb_typeof(message) <> 'array' then
        return 'message must be a JSON array, but is of type '||jsonb_typeof(message);
    end if;

    if jsonb_array_length(message) = 0 then
        return 'message is empty';
    end if;

    for i in 0..jsonb_array_length(message)-1 loop
        elem := message->i;

        case jsonb_typeof(elem)
        when 'string' then
            if message->>i = '' then
                return 'string must not be empty';
            end if;

        when 'object' then
            if (select count(*) from jsonb_object_keys(elem)) <> 1 then
                return 'JSON object must have exactly one key';
            end if;

            select * into k, v from jsonb_each(elem);

            if jsonb_typeof(v) <> 'string' then
                return 'JSON object value must be string, but is '||jsonb_typeof(v);
            end if;

            case k
            when 'b', 'i', 's' then
                null;
            when 'user' then
                if (select not exists(select from public.user where id = (elem->>k)::uuid)) then
                    return 'referenced user does not exist: '||(elem->>k);
                end if;
            when 'document' then
                if (select not exists(select from public.document where id = (elem->>k)::uuid)) then
                    return 'referenced document does not exist: '||(elem->>k);
                end if;
            else
                return 'invalid JSON object key "'||k||'"';
            end case;

        when 'array' then
            return 'JSON array not allowed in message';
        when 'number' then
            return 'JSON number not allowed in message';
        when 'boolean' then
            return 'JSON boolean not allowed in message';
        when 'null' then
            return 'JSON null not allowed in message';
        end case;
    end loop;

    return null;
end
$$;

comment on function work.validate_group_chat_message is 'Returns a non null error description if the passed JSON message is not valid';

----

create function work.create_group_chat(group_id uuid, message jsonb, created_by uuid) returns work.group_chat
language sql volatile strict as
$$
    insert into
        work.group_chat (
            group_id,
            message,
            created_by
        )
        values (
            create_group_chat.group_id,
            create_group_chat.message,
            create_group_chat.created_by
        )
    returning *
$$;

comment on function work.create_group_chat is 'Inserts and returns a new group chat message';

----

create function work.create_group_chat_reply(reply_to uuid, message jsonb, created_by uuid) returns work.group_chat
language sql volatile strict as
$$
    insert into work.group_chat (
        group_id,
        reply_to,
        message,
        created_by
    )
    select
        ref.group_id,
        create_group_chat_reply.reply_to,
        create_group_chat_reply.message,
        create_group_chat_reply.created_by
    from work.group_chat as ref
    where ref.id = create_group_chat_reply.reply_to
    returning *
$$;

comment on function work.create_group_chat_reply is 'Inserts and returns a new group chat reply to another message';

----

create function work.group_chat_message_to_string(message jsonb) returns text
language plpgsql immutable as
$$
declare
    result text not null = '';
begin
    for i in 0..jsonb_array_length(message)-1 loop
        if jsonb_typeof(message->i) = 'string' then
            result := result || (message->>i);
        else
            result := result || (select "value" from jsonb_each_text(message->i) limit 1);
        end if;
    end loop;

    return result;
end
$$;

comment on function work.group_chat_message_to_string is 'Formats a JSON chat message as plaintext string';

----

create function work.group_chat_message_string(chat work.group_chat) returns text
language sql stable strict as
$$
    select coalesce(
        work.validate_group_chat_message(chat.message),
        work.group_chat_message_to_string(chat.message)
    )
$$;

comment on function work.group_chat_message_string is 'Returns the chat message as plaintext string, or an error string';

----

create function work.group_chat_message_mentioned_user_ids(chat work.group_chat) returns uuid[]
language sql stable strict as
$$
    select array_agg(distinct((value->>'user')::uuid))
    from jsonb_array_elements(chat.message)
    where value->>'user' is not null
$$;

comment on function work.group_chat_message_mentioned_user_ids is 'Returns unique userIds mentionen in the chat message in random order';

----

create function work.group_chat_message_mentioned_users(chat work.group_chat) returns setof public.user
language sql stable strict as
$$
    select * from public.user
    where id = any(work.group_chat_message_mentioned_user_ids(chat))
$$;

comment on function work.group_chat_message_mentioned_users is 'Returns the users mentionen in the chat message in random order';

----

create function work.group_chat_message_mentioned_document_ids(chat work.group_chat) returns uuid[]
language sql stable strict as
$$
    select array_agg(distinct((value->>'document')::uuid))
    from jsonb_array_elements(chat.message)
    where value->>'document' is not null
$$;

comment on function work.group_chat_message_mentioned_document_ids is 'Returns unique documentIds mentionen in the chat message in random order';

----

create function work.group_chat_message_mentioned_documents(chat work.group_chat) returns setof public.document
language sql stable strict as
$$
    select * from public.document
    where id = any(work.group_chat_message_mentioned_document_ids(chat))
$$;

comment on function work.group_chat_message_mentioned_documents is 'Returns the documents mentionen in the chat message in random order';

----

create function work.group_chat_thread(chat work.group_chat) returns setof work.group_chat
language sql stable strict as
$$
    select *
    from work.group_chat
    where id = group_chat_thread.chat.id or reply_to = group_chat_thread.chat.id
    order by created_at
$$;

comment on function work.group_chat_thread is 'Returns the complete chat thread including and in reply to a chat message';

----

create function work.get_group_document_chat(group_id uuid, document_id uuid) returns setof work.group_chat
language sql stable strict as
$$
    select *
    from work.group_chat
    where group_chat.group_id = get_group_document_chat.group_id
        and message @> jsonb_build_object('document', get_group_document_chat.document_id)
    order by created_at
$$;

comment on function work.get_group_document_chat is 'Returns the group chat mentioning a document ID';








----

-- TODO this does not represent chat threads, is it useful at all?
-- create function work.get_group_user_chat(group_id uuid, user_id uuid) returns setof work.group_chat
-- language sql stable strict as
-- $$
--     select *
--     from work.group_chat
--     where group_chat.group_id = get_group_user_chat.group_id
--         and (
--             created_by = get_group_user_chat.user_id
--             or
--             message @> jsonb_build_object('user', get_group_user_chat.user_id)
--         )
--     order by created_at
-- $$;

-- comment on function work.get_group_user_chat is 'Returns the group chat from a user and mentioning a user ID';