create table public.document_comment (
  id uuid primary key default uuid_generate_v4(),

  document_id uuid not null references public.document(id) on delete cascade,

  reply_to     uuid references public.document_comment(id) on delete cascade,
  commented_by uuid not null
      default '08a34dc4-6e9a-4d61-b395-d123005e65d3' -- system-user ID for unknown user
      references public.user(id) on delete set default,

  message jsonb not null,
  constraint message_validation check(
    message is not null
    and jsonb_typeof(message) = 'array'
    and jsonb_array_length(message) > 0),

  related_document_approval_request_id  uuid references public.document_approval_request(id) on delete cascade,
  related_document_approval_id          uuid references public.document_approval(id) on delete cascade,
  related_document_workflow_step_log_id uuid references public.document_workflow_step_log(id) on delete cascade,
  constraint only_one_or_none_related_element check(
    case
      when related_document_approval_request_id is not null
        then related_document_approval_id is null
        and related_document_workflow_step_log_id is null

      when related_document_approval_id is not null
        then related_document_approval_request_id is null
        and related_document_workflow_step_log_id is null

      when related_document_workflow_step_log_id is not null
        then related_document_approval_request_id is null
        and related_document_approval_id is null

      else true
    end
  ),

  -- no `updated_at` because comments are immutable
  created_at created_time not null
);

comment on column public.document_comment.reply_to is '@deprecated';

grant select, insert, delete on public.document_comment to domonda_user;
grant select, insert, delete on public.document_comment to domonda_wg_user;

create index document_comment_document_id_idx on public.document_comment (document_id);
create index document_comment_commented_by_idx on public.document_comment (commented_by);
create index document_comment_reply_to_idx on public.document_comment (reply_to);
create index document_comment_message_idx on public.document_comment (message);
create index document_comment_related_document_approval_request_id_idx on public.document_comment (related_document_approval_request_id);
create index document_comment_related_document_approval_id_idx on public.document_comment (related_document_approval_id);
create index document_comment_related_document_workflow_step_log_id_idx on public.document_comment (related_document_workflow_step_log_id);

create function public.document_comment_message_mentioned_user_ids(
  message jsonb
) returns uuid[] as $$
  select
    array_agg((value->>'user')::uuid)
  from jsonb_array_elements(message)
  where value->'user' is not null
$$ language sql immutable strict;
create index document_comment_message_mentioned_user_ids_idx on public.document_comment (public.document_comment_message_mentioned_user_ids(document_comment.message));

create function public.document_comment_mentioned_user_ids(
  document_comment public.document_comment
) returns uuid[] as $$
  select * from public.document_comment_message_mentioned_user_ids(document_comment.message)
$$ language sql immutable strict;
create index document_comment_mentioned_user_ids_idx on public.document_comment (public.document_comment_mentioned_user_ids(document_comment));

-- TODO use work.validate_group_chat_message when the work domain has stabilized
create function private.validate_document_comment_message(message jsonb) returns jsonb
language plpgsql as
$$
declare
    elem jsonb;
    k    text;
    v    jsonb;
begin
    if message is null then
        raise exception 'message is NULL';
    end if;

    if jsonb_typeof(message) <> 'array' then
        raise exception 'message must be a JSON array, but is of type %', jsonb_typeof(message);
    end if;

    if jsonb_array_length(message) = 0 then
        raise exception 'message is empty';
    end if;

    for i in 0..jsonb_array_length(message)-1 loop
        elem := message->i;

        case jsonb_typeof(elem)
        when 'string' then
            if message->>i = '' then
                raise exception 'string must not be empty';
            end if;

        when 'object' then
            if (select count(*) from jsonb_object_keys(elem)) <> 1 then
                raise exception 'JSON object must have exactly one key';
            end if;

            select * into k, v from jsonb_each(elem);

            if jsonb_typeof(v) <> 'string' then
                raise exception 'JSON object value must be string, but is %', jsonb_typeof(v);
            end if;

            case k
            when 'b', 'i', 's' then
                null;
            when 'user' then
                if (select not exists(select from public.user where id = (elem->>k)::uuid)) then
                    raise exception 'referenced user does not exist: %', (elem->>k);
                end if;
            when 'document' then
                if (select not exists(select from public.document where id = (elem->>k)::uuid)) then
                    raise exception 'referenced document does not exist: %', (elem->>k);
                end if;
            else
                raise exception 'invalid JSON object key "%', k||'"';
            end case;

        when 'array' then
            raise exception 'JSON array not allowed in message';
        when 'number' then
            raise exception 'JSON number not allowed in message';
        when 'boolean' then
            raise exception 'JSON boolean not allowed in message';
        when 'null' then
            raise exception 'JSON null not allowed in message';
        end case;
    end loop;

    return message;
end
$$;

comment on function private.validate_document_comment_message is 'Raises an exception if the passed JSON message is not valid';

create type public.document_comment_message_part as (
  normal text, -- just normal text, without any formatting
  bold   text,
  italic text,

  document_id uuid,
  user_id     uuid
);

comment on type public.document_comment_message_part is $$
@foreignKey (document_id) references public.document (id)
@foreignKey (user_id) references public.user (id)$$;

create function public.parts_of_document_comment_message(
  message jsonb
) returns setof public.document_comment_message_part as $$
  select
    value->>0 as normal,
    value->>'b' as bold,
    value->>'i' as italic,
    (value->>'document')::uuid as document_id,
    (value->>'user')::uuid as user_id
  from jsonb_array_elements(message)
$$ language sql immutable strict;

create function public.document_comment_message_parts(
  document_comment public.document_comment
) returns setof public.document_comment_message_part as $$
  select * from public.parts_of_document_comment_message(document_comment.message)
$$ language sql immutable strict;

create function public.document_comment_replies_and_their_replies(
  document_comment public.document_comment
) returns setof public.document_comment as $$
  with recursive reply as (
    select * from public.document_comment where reply_to = document_comment_replies_and_their_replies.document_comment.id
    union all
    select document_comment.* from reply, public.document_comment
    where document_comment.reply_to = reply.id
  )
  select * from reply
  order by created_at asc -- newest on bottom
$$ language sql stable strict;

create function public.document_comment_commented_by_current_user(
  document_comment public.document_comment
) returns boolean as $$
  select document_comment.commented_by = private.current_user_id()
$$ language sql stable strict;

comment on function public.document_comment_commented_by_current_user is '@notNull';

create function public.document_comment_text_message(
    document_comment public.document_comment
) returns text as $$
  select trim(string_agg(
    coalesce(
      part.normal,
      part.bold,
      part.italic,
      (select public.user_full_name("user") from public."user" where "user".id = part.user_id),
      (select public.document_derived_title(document) from public.document where document.id = part.document_id),
      '' -- coalesce fallback
    ),
    '' -- string_agg separator
  ))
  from public.document_comment_message_parts(document_comment) as part
$$ language sql immutable strict;
comment on function public.document_comment_text_message is '@notNull';

----

create function public.create_document_comment(
  document_id  uuid,
  message      jsonb,
  related_document_approval_request_id uuid = null,
  related_document_approval_id uuid = null,
  related_document_workflow_step_log_id uuid = null,
  reply_to     uuid = null -- deprecated
) returns public.document_comment as $$
declare
  document_client_company_id uuid;
  created_document_comment public.document_comment;
  part public.document_comment_message_part;
  created_work_group_id uuid;
begin
  if not public.can_current_user_comment_on_document(create_document_comment.document_id)
  then
    raise exception 'Forbidden';
  end if;

  select client_company_id into document_client_company_id
  from public.document
  where document.id = create_document_comment.document_id;

  insert into public.document_comment (
    document_id,
    message,
    related_document_approval_request_id,
    related_document_approval_id,
    related_document_workflow_step_log_id,
    reply_to,
    commented_by
  ) values (
    create_document_comment.document_id,
    private.validate_document_comment_message(create_document_comment.message),
    create_document_comment.related_document_approval_request_id,
    create_document_comment.related_document_approval_id,
    create_document_comment.related_document_workflow_step_log_id,
    create_document_comment.reply_to,
    private.current_user_id()
  )
  returning * into created_document_comment;

  -- share document with user if not already
  for part
  in (select * from public.document_comment_message_parts(created_document_comment))
  loop
    if part.user_id is null
    then continue;
    end if;

    if (select "type" <> 'EXTERNAL'
      from public.user
      where "user".id = part.user_id)
    then continue; -- Only external users can be invited
    end if;

    if not exists(select from public.document, public.document_shared_with(document)
      where document.id = create_document_comment.document_id
      and document_shared_with.id = part.user_id)
    then
      if not public.user_has_admin_access_for_client_company(
        private.current_user(),
        document_client_company_id
      )
      then
        raise exception 'Document sharing forbidden';
      end if;

      select id into created_work_group_id from work.create_group(
        document_client_company_id,
        'ShareDocumentMention',
        'SHARE_DOCUMENT_MENTION_' || create_document_comment.document_id || '_' || now()::text -- TODO: use rfc date formating
      );

      insert into work.group_user (group_id, user_id, rights_id, added_by)
      values (created_work_group_id, part.user_id, work.rights_id_comment_on_documents_only(), private.current_user_id());

      insert into work.group_document (group_id, document_id, added_by)
      values (created_work_group_id, create_document_comment.document_id, private.current_user_id());

      -- log
      insert into public.document_log ("type", document_id, user_id, share_user_id)
      values ('SHARE', create_document_comment.document_id, private.current_user_id(), part.user_id);
    end if;
  end loop;

  return created_document_comment;
end
$$ language plpgsql volatile
security definer;

create function public.delete_document_comment(
  id uuid
) returns public.document_comment as $$
  delete from public.document_comment
  where id = delete_document_comment.id
  returning *
$$ language sql volatile strict;

create function public.set_document_workflow_step_and_comment(
  document_id      uuid,
  workflow_step_id uuid = null, -- can be unset
  message          jsonb = null
) returns public.document as $$
declare
  doc public.document;
  document_workflow_step_log_id uuid;
  curr_workflow_step_id uuid;
  next_workflow_step_id uuid := set_document_workflow_step_and_comment.workflow_step_id;
begin
  set local current.disable_document_workflow_step_logging to true;

  select document.workflow_step_id into curr_workflow_step_id
  from public.document
  where document.id = set_document_workflow_step_and_comment.document_id;

  -- if the new document workflow step is null OR prev/next step of the currently active step (following the "index")
  if (
    with dws as (
      select dws.* from public.document as d
        inner join public.document_workflow_step as dws on (dws.id = d.workflow_step_id)
      where (d.id = set_document_workflow_step_and_comment.document_id)
    )
    select set_document_workflow_step_and_comment.workflow_step_id is null
      or prev_step.id = set_document_workflow_step_and_comment.workflow_step_id
      or next_step.id = set_document_workflow_step_and_comment.workflow_step_id
    from
      dws,
      public.document_workflow_step_protected_previous_step(dws) as prev_step,
      public.document_workflow_step_protected_next_step(dws) as next_step
  ) then
    -- if the user doesn't have access to the current step, he shouldn't be able to push the document anywhere
    if not exists (select from document
      where id = document_id
      and public.document_can_current_user_change(document))
    then
      raise exception 'Forbidden';
    end if;

    -- the function below is defined as `security definer` so that the user can
    -- perform the action even if he does not have access to the prev/next step
    perform private.update_workflow_step_for_document(
      set_document_workflow_step_and_comment.document_id,
      set_document_workflow_step_and_comment.workflow_step_id
    );

  else

    -- perform a regular update if the new document workflow step is neither the prev/next step
    update public.document
    set workflow_step_id=set_document_workflow_step_and_comment.workflow_step_id, updated_at=now()
    where document.id = set_document_workflow_step_and_comment.document_id;

  end if;

  -- we create a log entry manually, auto-logging is disabled
  if next_workflow_step_id is distinct from curr_workflow_step_id
  then
    document_workflow_step_log_id := uuid_generate_v4();
    insert into public.document_workflow_step_log (id, user_id, document_id, prev_id, next_id)
    values (
      document_workflow_step_log_id,
      private.current_user_id(),
      set_document_workflow_step_and_comment.document_id,
      curr_workflow_step_id,
      next_workflow_step_id
    );
  end if;

  -- comment if there is a message
  if set_document_workflow_step_and_comment.message is not null then
    perform public.create_document_comment(
      document_id=>set_document_workflow_step_and_comment.document_id,
      message=>set_document_workflow_step_and_comment.message,
      related_document_workflow_step_log_id=>document_workflow_step_log_id
    );
  end if;

  -- we re-select the document and return it. if the user does not have access to
  -- the next document, the select will return null.
  -- we MUST select after the workflow step log for users with access restrictions
  select * into doc from public.document
  where (id = set_document_workflow_step_and_comment.document_id);

  reset current.disable_document_workflow_step_logging;
  return doc;
end
$$ language plpgsql volatile;

create function public.approve_document_and_comment(
  request_id uuid,
  message    jsonb = null
) returns public.document_approval as $$
declare
  doc_app public.document_approval;
begin
  insert into public.document_approval (request_id, approver_id)
    values (approve_document_and_comment.request_id, private.current_user_id())
  returning * into doc_app;

  -- comment if there is a message
  if approve_document_and_comment.message is not null then
    perform public.create_document_comment(
      document_id=>(select document_id from public.document_approval_request where id = doc_app.request_id),
      message=>approve_document_and_comment.message,
      related_document_approval_id=>doc_app.id
    );
  end if;

  return doc_app;
end
$$ language plpgsql volatile;

---- document_comment_seen

create table public.document_comment_seen (
  document_comment_id uuid not null references public.document_comment(id) on delete cascade,
  seen_by            uuid not null references public.user(id) on delete cascade,
  primary key (document_comment_id, seen_by),

  created_at created_time not null
);

grant select, insert on public.document_comment_seen to domonda_user;
grant select, insert on public.document_comment_seen to domonda_wg_user;

create index document_comment_seen_document_comment_id_idx on public.document_comment_seen (document_comment_id);
create index document_comment_seen_seen_by_idx on public.document_comment_seen (seen_by);

create function public.create_document_comment_seen(
  document_comment_id uuid,
  seen_by uuid = private.current_user_id()
) returns public.document_comment_seen as $$
  insert into public.document_comment_seen (document_comment_id, seen_by)
  values (
    create_document_comment_seen.document_comment_id,
    create_document_comment_seen.seen_by
  )
  returning *
$$ language sql volatile;

create function public.document_comment_seen_by_current_user(
  document_comment public.document_comment
) returns boolean as $$
  select public.document_comment_commented_by_current_user(document_comment)
  or exists (select from public.document_comment_seen
    where document_comment_id = document_comment.id
    and seen_by = private.current_user_id())
$$ language sql stable strict;

comment on function public.document_comment_seen_by_current_user is '@notNull';

create function public.document_unseen_document_comments(
  document public.document
) returns setof public.document_comment as $$
  select * from public.document_comment
  where document_comment.document_id = document.id
  and not public.document_comment_seen_by_current_user(document_comment)
$$ language sql stable;

---- document_comment_like

create table public.document_comment_like (
  document_comment_id uuid not null references public.document_comment(id) on delete cascade,
  liked_by            uuid not null references public.user(id) on delete cascade,
  primary key (document_comment_id, liked_by),

  created_at created_time not null
);

grant select, insert, delete on public.document_comment_like to domonda_user;
grant select, insert, delete on public.document_comment_like to domonda_wg_user;

create index document_comment_like_document_comment_id_idx on public.document_comment_like (document_comment_id);
create index document_comment_like_liked_by_idx on public.document_comment_like (liked_by);

create function public.create_document_comment_like(
  document_comment_id uuid,
  liked_by uuid = private.current_user_id()
) returns public.document_comment_like as $$
  insert into public.document_comment_like (document_comment_id, liked_by)
  values (
    create_document_comment_like.document_comment_id,
    create_document_comment_like.liked_by
  )
  returning *
$$ language sql volatile;

create function public.delete_document_comment_like(
  document_comment_id uuid,
  liked_by uuid = private.current_user_id()
) returns public.document_comment_like as $$
  delete from public.document_comment_like
  where document_comment_id = delete_document_comment_like.document_comment_id
  and liked_by = delete_document_comment_like.liked_by
  returning *
$$ language sql volatile strict;

create function public.document_comment_liked_by_current_user(
  document_comment public.document_comment
) returns boolean as $$
  select exists (select from public.document_comment_like
    where document_comment_id = document_comment.id
    and liked_by = private.current_user_id())
$$ language sql stable strict;

comment on function public.document_comment_liked_by_current_user is '@notNull';
