create trigger gql_document_changed
  after update on public.document
  for each row
  when (
    (old.category_id is distinct from new.category_id)
    or (old.workflow_step_id is distinct from new.workflow_step_id)
    or (old.superseded is distinct from new.superseded)
    or (old.checkout_user_id is distinct from new.checkout_user_id)
    or (old.checkout_reason is distinct from new.checkout_reason)
    or (old.archived is distinct from new.archived)
  )
  execute procedure private.gql_subscription(
    'documentChanged', -- event
    'documentChanged:id=$1', -- topic
    'id' -- subjects
  );

-- approval request issued
create trigger gql_document_changed_because_document_approval_request
  after insert on public.document_approval_request
  for each row
  execute procedure private.gql_subscription(
    'documentHasNewApprovalRequest', -- event
    'documentChanged:id=$1', -- topic
    'document_id' -- subjects
  );

-- locked unlocked
create trigger gql_document_changed_because_docdb_locked_document
  after insert or delete on docdb.locked_document
  for each row
  execute procedure private.gql_subscription(
    'documentLockedOrUnlocked', -- event
    'documentChanged:id=$1', -- topic
    'document_id' -- subjects
  );

-- rule notifications status changed
create function private.gql_document_changed_because_rule_notifications_status_changed()
returns trigger as $$
declare
    trigger_table text := (tg_table_schema || '.' || tg_table_name);
    document_id   uuid;
begin
  if trigger_table = 'private.notification'
  then

    if tg_op = 'UPDATE'
    and old.sent_at is not distinct from new.sent_at
    then
      -- no relevant status update
      return new;
    end if;

    select
      send_notification_log.document_id into document_id
    from rule.send_notification_log
    where send_notification_log.notification_id = new.id;

  end if;

  if trigger_table = 'worker.job'
  then

    if tg_op = 'UPDATE'
    and old.started_at is not distinct from new.started_at
    and old.stopped_at is not distinct from new.stopped_at
    and old.error_msg is not distinct from new.error_msg
    then
      -- no relevant status update
      return new;
    end if;

    select
      send_notification_log.document_id into document_id
    from rule.send_notification_log
    where send_notification_log.notification_id = (new.payload->>'NotificationID')::uuid;

  end if;

  if document_id is null then
    -- no document for status update found
    return new;
  end if;

  -- see private/gql_subscription.sql
  perform pg_notify('documentChanged:id='||document_id::text, json_build_object(
    'event', 'documentNotificationsStatusChanged',
    'subjects', array[document_id]
  )::text);

  return new;
end
$$ language plpgsql stable strict;

create trigger gql_document_changed_notifications_changed
  after insert or update on private.notification
  for each row
  execute procedure private.gql_document_changed_because_rule_notifications_status_changed();

create trigger gql_document_changed_notification_jobs_changed
  after insert or update on worker.job
  for each row
  when (new."type" = 'NOTIFICATION')
  execute procedure private.gql_document_changed_because_rule_notifications_status_changed();
