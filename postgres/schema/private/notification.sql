-- TODO-db-210802 send mail document workflow changed from rules

create type private.notification_type as enum (
  'DOMONDA_UPDATE',
  'DOCUMENT_APPROVAL_REQUEST',
  'DOCUMENT_COMMENT_MENTION',
  'DOCUMENT_COMMENT_REPLY_TO_MENTION',
  'DOCUMENT_INFO',
  'DOCUMENT_UPDATE',
  'DOCUMENT_CONTRACT_EXPIRY',
  'DOCUMENT_CONTRACT_RESUBMISSION',
  'DOCUMENT_PAYMENT_REMINDER'
);

-- intentionally public, see create_notification_reaction.sql
create type public.notification_destination as enum (
  'EMAIL',
  'WEBHOOK'
  -- in the future: PUSH, WEB, SMS, etc.
);

create table private.notification (
  id uuid primary key default uuid_generate_v4(),

  "type"      private.notification_type not null,
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
  constraint email_receiver_check check(
    (destination <> 'EMAIL')
    or (
      (receiver_user_id is not null) or (receiver_email is not null)
    )
  ),
  constraint webhook_receiver_check check(
    (destination <> 'WEBHOOK')
    or (
      receiver_url is not null
    )
  ),
  constraint receiver_must_be_user_check check(
    ("type" <> 'DOMONDA_UPDATE')
    or ("type" <> 'DOCUMENT_APPROVAL_REQUEST')
    or ("type" <> 'DOCUMENT_COMMENT_MENTION')
    or ("type" <> 'DOCUMENT_UPDATE')
    or (
      receiver_user_id is not null
    )
  ),

  payload jsonb,

  send_at timestamptz not null, -- when to send
  sent_at timestamptz,          -- when was send (when null, not sent only queued)

  updated_at updated_time,
  created_at created_time
);

create index notification_type_idx on private.notification ("type");
create index notification_destination_idx on private.notification (destination);
create index notification_receiver_user_id_idx on private.notification (receiver_user_id);

create function private.notification_create_or_update_job()
returns trigger as $$
declare
  notif        private.notification;
  existing_job worker.job;
begin
  notif := new;

  if notif.sent_at then
    -- nothing to do if the notification is sent out
    return null;
  end if;

  select * into existing_job
  from worker.job
  where job."type" = 'NOTIFICATION'
    and payload->>'NotificationID' = notif.id::text
    and started_at is null
  for update;

  if existing_job is null then

    insert into worker.job ("type", payload, priority, origin, max_retry_count, start_at)
    values (
      'NOTIFICATION',
      jsonb_build_object(
        'NotificationID', notif.id,
        'Type', notif."type",
        'Destination', notif.destination,
        'ReceiverUserEmail', (select email from public."user" where "user".id = notif.receiver_user_id),
        'ReceiverEmail', notif.receiver_email,
        'ReceiverURL', notif.receiver_url
      ),
      0,
      'private.notification_create_or_update_job()',
      3,
      notif.send_at
    );

  elsif notif.send_at is not null then

    -- update starting time for debounced notification
    update worker.job
      set
        start_at=notif.send_at,
        updated_at=now()
    where id = existing_job.id;

  end if;

  return null;
end
$$ language plpgsql volatile security definer;
create trigger insert_notification_create_or_update_job_trigger
  after insert on private.notification
  for each row
  when (new.sent_at is null)
  execute procedure private.notification_create_or_update_job();
create trigger update_notification_create_or_update_job_trigger
  after update on private.notification
  for each row
  when (new.sent_at is null and
    old.send_at is distinct from new.send_at)
  execute procedure private.notification_create_or_update_job();

create function private.notification_delete_job()
returns trigger as $$
declare
  notif        private.notification;
  existing_job worker.job;
begin
  notif := old;

  select * into existing_job
  from worker.job
  where job."type" = 'NOTIFICATION'
  and payload->>'NotificationID' = notif.id::text;

  if existing_job is null
  then
    return null;
  end if;

  if existing_job.started_at is not null
  then
    raise exception 'Cannot delete notification because its job has been started';
  end if;

  delete from worker.job
  where id = existing_job.id;

  return null;
end
$$ language plpgsql volatile security definer;
create trigger notification_delete_job_trigger
  after delete on private.notification
  for each row
  execute procedure private.notification_delete_job();

----

create type public.notification_status as enum (
  'WAITING',
  'SENDING',
  'ERROR',
  'SENT'
);

create function private.status_of_notification(
  notif_id uuid
) returns public.notification_status as $$
  select (case
    when notif.sent_at is not null
      then 'SENT'
    when exists(select from worker.job
      where job."type" = 'NOTIFICATION'
      and payload->>'NotificationID' = notif.id::text
      and stopped_at is not null
      and error_msg is not null)
      then 'ERROR'
    when exists(select from worker.job
      where job."type" = 'NOTIFICATION'
      and payload->>'NotificationID' = notif.id::text
      and started_at is not null)
      then 'SENDING'
    else 'WAITING'
  end)::public.notification_status
  from private.notification as notif
  where notif.id = notif_id
$$ language sql stable strict
security definer;

----

create function private.notify_document_approval_request()
returns trigger as $$
declare
  document_id       uuid;
  receiver_id       uuid;
  notif_payload     jsonb;
  debouncable_notif private.notification;
  debounce_timeout  interval := interval '10 mins';
begin
  document_id := new.document_id;

  -- loop over all users in a group, or the direct user
  for receiver_id in (
    select
      coalesce(user_group_user.user_id, document_approval_request.approver_id)
    from public.document_approval_request
      left join (
        public.user_group
        inner join public.user_group_user on user_group_user.user_group_id = user_group.id
      ) on user_group.id = document_approval_request.user_group_id
    where document_approval_request.id = new.id
    and coalesce(user_group_user.user_id, document_approval_request.approver_id) is not null -- a user group might be empty, so there's no notification to issue
  )
  loop
    if new.approver_id is not null and not (
      select document_direct_approval_request_notification from public.user
      where id = receiver_id
    ) then
      -- user opted out
      continue;
    end if;

    if new.user_group_id is not null and not (
      select document_group_approval_request_notification from public.user
      where id = receiver_id
    ) then
      -- user opted out
      continue;
    end if;

    if exists (select from public.user
      where "user".id = receiver_id
      and not "user".enabled)
    then
      -- disabled users cannot be notified
      continue;
    end if;

    select * into debouncable_notif
    from private.notification
    where "type" = 'DOCUMENT_APPROVAL_REQUEST'
    and receiver_user_id = receiver_id
    and sent_at is null -- not sent yet
    for update;

    notif_payload := jsonb_agg(document_id);

    if debouncable_notif is null and not exists(
      -- related job not started yet
      select from worker.job
      where "type" = 'NOTIFICATION'
      and payload->>'NotificationID' = debouncable_notif.id::text
      and started_at is null
      for update
    ) then
      -- there is no debouncable notification, create one

      insert into private.notification ("type", destination, receiver_user_id, payload, send_at)
      values (
        'DOCUMENT_APPROVAL_REQUEST',
        'EMAIL',
        receiver_id,
        notif_payload,
        (now() + debounce_timeout)
      );

    else
      -- there is a debouncable notification, concatanate payload and debounce

      update private.notification
        set
          payload=notification.payload || notif_payload,
          send_at=(now() + debounce_timeout),
          updated_at=now()
      where id = debouncable_notif.id;

    end if;
  end loop;

  return null;
end
$$ language plpgsql volatile security definer;
create trigger notify_document_approval_request_trigger
  after insert on public.document_approval_request
  for each row
  when (new.approver_id is not null or new.user_group_id is not null) -- only direct and user group requests
  execute procedure private.notify_document_approval_request();

create function private.notify_document_approval_canceled()
returns trigger as $$
declare
  document_id    uuid;
  receiver_id    uuid;
  existing_notif private.notification;
begin
  select document_approval_request.document_id into document_id
  from public.document_approval_request
  where document_approval_request.id = new.request_id;

  -- loop over all users in a group, or the direct user
  for receiver_id in (
    select
      coalesce(user_group_user.user_id, document_approval_request.approver_id)
    from public.document_approval_request
      left join (
        public.user_group
        inner join public.user_group_user on user_group_user.user_group_id = user_group.id
      ) on user_group.id = document_approval_request.user_group_id
    where document_approval_request.id = new.request_id
  )
  loop
    select * into existing_notif
    from private.notification
    where "type" = 'DOCUMENT_APPROVAL_REQUEST'
    and receiver_user_id = receiver_id
    and private.status_of_notification(notification.id) = 'WAITING'
    and payload ? document_id::text -- about the document having the canceled approval
    for update;

    if existing_notif is null
    then
      continue;
    end if;

    -- omit the document with the canceled approval request from the payload
    existing_notif.payload = (
      select jsonb_agg(value)
      from jsonb_array_elements(existing_notif.payload)
      where value <> to_jsonb(document_id)
    );

    if existing_notif.payload is null
    then
      -- notification about only the document whose approval request was canceled
      delete from private.notification
      where id = existing_notif.id;
    else
      -- notification about more documents and only one had the request canceled
      update private.notification
        set
          payload=existing_notif.payload,
          updated_at=now()
      where id = existing_notif.id;
    end if;
  end loop;

  -- TODO: race conditions?

  return null;
end
$$ language plpgsql volatile security definer;
create trigger notify_document_approval_canceled_trigger
  after insert on public.document_approval
  for each row
  when (new.canceled)
  execute procedure private.notify_document_approval_canceled();

create function private.notify_document_comment_mention()
returns trigger as $$
declare
  document_comment public.document_comment;
  receiver_id               uuid;
  notif_payload             jsonb;
  debouncable_notif         private.notification;
  debounce_timeout          interval := interval '10 mins';
begin
  document_comment := new;

  if private.current_setting_flag('current.disable_notify_document_comment_mention')
  then
    -- for example: when sharing a document with a note, the external user should receive just the invite notification
    return null;
  end if;

  for receiver_id in (
    select part.user_id
    from public.document_comment_message_parts(document_comment) as part
    where part.user_id is not null)
  loop
    if exists (select from public.user
      where "user".id = receiver_id
      and not "user".enabled)
    then
      -- disabled users cannot be notified
      continue;
    end if;

    if exists (select from public.user
      where "user".id = receiver_id
      and "user".email is null)
    then
      -- email-less users cannot be notified
      continue;
    end if;

    select * into debouncable_notif
    from private.notification
    where "type" = 'DOCUMENT_COMMENT_MENTION'
    and receiver_user_id = receiver_id
    and sent_at is null -- not sent yet
    for update;

    notif_payload := jsonb_agg(document_comment.id);

    if debouncable_notif is null and not exists(
      -- related job not started yet
      select from worker.job
      where "type" = 'NOTIFICATION'
      and payload->>'NotificationID' = debouncable_notif.id::text
      and started_at is null
      for update
    ) then
      -- there is no debouncable notification, create one

      insert into private.notification ("type", destination, receiver_user_id, payload, send_at)
      values (
        'DOCUMENT_COMMENT_MENTION',
        'EMAIL',
        receiver_id,
        notif_payload,
        (now() + debounce_timeout)
      );

    else
      -- there is a debouncable notification, concatanate payload and debounce

      update private.notification
        set
          payload=notification.payload || notif_payload,
          send_at=(now() + debounce_timeout),
          updated_at=now()
      where id = debouncable_notif.id;

    end if;

  end loop;

  return null;
end
$$ language plpgsql volatile security definer;
create trigger notify_document_comment_mention_trigger
  after insert on public.document_comment
  for each row
  execute procedure private.notify_document_comment_mention();

create function private.notify_document_comment_reply_to_mention()
returns trigger as $$
declare
  receiver_id       uuid;
  notif_payload     jsonb;
  debouncable_notif private.notification;
  debounce_timeout  interval := interval '10 mins';
begin
  if private.current_setting_flag('current.disable_notify_document_comment_reply_to_mention')
  then
    -- for example: when sharing a document with a note, the external user should receive just the invite notification
    return null;
  end if;

  for receiver_id in (
    select document_comment.commented_by
    from public.document_comment
    -- not the same comment
    where document_comment.id <> new.id
    -- not self
    and document_comment.commented_by <> new.commented_by
    -- on the same document
    and document_comment.document_id = new.document_id
    -- that mentions the user currently leaving a comment
    and new.commented_by in (select part.user_id
      from public.document_comment_message_parts(document_comment) as part)
  )
  loop
    if exists (select from public.user
      where "user".id = receiver_id
      and not "user".enabled)
    then
      -- disabled users cannot be notified
      continue;
    end if;

    if exists (select from public.user
      where "user".id = receiver_id
      and "user".email is null)
    then
      -- email-less users cannot be notified
      continue;
    end if;

    select * into debouncable_notif
    from private.notification
    where "type" = 'DOCUMENT_COMMENT_REPLY_TO_MENTION'
    and receiver_user_id = receiver_id
    and sent_at is null -- not sent yet
    for update;

    notif_payload := jsonb_agg(new.id);

    if debouncable_notif is null and not exists(
      -- related job not started yet
      select from worker.job
      where "type" = 'NOTIFICATION'
      and payload->>'NotificationID' = debouncable_notif.id::text
      and started_at is null
      for update
    ) then
      -- there is no debouncable notification, create one

      insert into private.notification ("type", destination, receiver_user_id, payload, send_at)
      values (
        'DOCUMENT_COMMENT_REPLY_TO_MENTION',
        'EMAIL',
        receiver_id,
        notif_payload,
        (now() + debounce_timeout)
      );

    else
      -- there is a debouncable notification, concatanate payload and debounce

      update private.notification
        set
          payload=notification.payload || notif_payload,
          send_at=(now() + debounce_timeout),
          updated_at=now()
      where id = debouncable_notif.id;

    end if;

  end loop;

  return null;
end
$$ language plpgsql volatile security definer;
create trigger notify_document_comment_reply_to_mention_trigger
  after insert on public.document_comment
  for each row
  execute procedure private.notify_document_comment_reply_to_mention();

create function private.notify_document_info(
  destination public.notification_destination,
  document    public.document,

  note text = null,

  receiver_user_id uuid = null,
  receiver_email   public.email_addr = null,
  receiver_url     text = null,

  action_reaction_id uuid = null
) returns private.notification as $$
declare
  notif         private.notification;
  notif_payload jsonb;
begin
  notif_payload := public.document_snapshot(document);

  if note is not null then
    notif_payload := jsonb_set(
      notif_payload,
      '{note}',
      to_jsonb(note)
    );
  end if;

  if action_reaction_id is not null then
    notif_payload := jsonb_set(
      notif_payload,
      '{rule}',
      (select jsonb_build_object(
          'id', action_reaction.id,
          'name', rule.action_reaction_full_name(action_reaction))
        from rule.action_reaction
        where action_reaction.id = action_reaction_id)
    );
  end if;

  insert into private.notification (
    "type",
    destination,
    receiver_user_id,
    receiver_email,
    receiver_url,
    payload,
    send_at
  ) values (
    'DOCUMENT_INFO',
    notify_document_info.destination,
    notify_document_info.receiver_user_id,
    notify_document_info.receiver_email,
    notify_document_info.receiver_url,
    notif_payload,
    now()
  ) returning * into notif;

  return notif;
end
$$ language plpgsql volatile security definer;

create function private.notify_document_payment_reminder()
returns trigger as $$
declare
  notif_payload jsonb;
begin
  notif_payload := to_jsonb(new.id);

  insert into private.notification (
    "type",
    destination,
    receiver_email,
    payload,
    send_at
  ) values (
    'DOCUMENT_PAYMENT_REMINDER',
    'EMAIL',
    new.receiver,
    notif_payload,
    now()
  );

  return null;
end
$$ language plpgsql volatile security definer;
create trigger notify_document_payment_reminder_trigger
  after insert on public.document_payment_reminder
  for each row
  execute procedure private.notify_document_payment_reminder();
