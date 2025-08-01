create type public.document_history_type as enum (
  'NOTIFICATION',
  'IMPORTED',
  'EXPORT',
  'BOOKED',
  'BOOKING_CANCELED',
  'READY_FOR_BOOKING',
  'COMMENT',
  'APPROVAL_REQUESTED',
  'APPROVAL_FULFILLED',
  'WORKFLOW_STEP',
  'RULE_DOCUMENT',
  'RULE_INVOICE',
  'RULE_DOCUMENT_APPROVAL_REQUEST',
  'RULE_CANCEL_DOCUMENT_APPROVAL_REQUEST',
  'RULE_DOCUMENT_MACRO',
  'RULE_COULD_NOT_EXECUTE',
  'ADDED_TO_REVIEW',
  'REMOVED_FROM_REVIEW',
  'ARCHIVED',
  'UNARCHIVED',
  'DELETED',
  'RESTORED',
  'SHARE',
  'REVOKE_SHARE',
  'CLONED',
  'DERIVED',
  'OVERRIDE_PARTNER_PAYMENT_PRESET',
  'CATEGORY_CHANGED',
  'PAYMENT_REMINDER_SENT',
  'DOCUMENT_VERSION_USER_UPLOAD_UPDATE', -- DOCUMENT_VERSION_<document_version.commit_reason>
  'DOCUMENT_VERSION_USER_ATTACH_DOCUMENT_PAGES',
  'AUTOMATION_ACTION_ON_DOCUMENT'
);

----

create type public.document_history_preset as enum (
  'ALL',
  'IMPORTANT',
  'USER_ACTIVITIES',
  'APPROVAL_WORKFLOW',
  'COMMENT'
);

----

create function public.document_history_preset_filter(
  preset public.document_history_preset
) returns table (
  types             public.document_history_type[],
  exclude_types     boolean,
  exclude_rule_user boolean
) as $$
begin
  case preset
    when 'ALL' then
      return query select null::public.document_history_type[], false, false;
    when 'IMPORTANT' then
      return query
        select
          array[
            'IMPORTED',
            'BOOKED',
            'BOOKING_CANCELED',
            'COMMENT',
            'APPROVAL_REQUESTED',
            'APPROVAL_FULFILLED',
            'WORKFLOW_STEP',
            'ARCHIVED',
            'UNARCHIVED',
            'DELETED',
            'RESTORED',
            'SHARE',
            'REVOKE_SHARE',
            'OVERRIDE_PARTNER_PAYMENT_PRESET',
            'CATEGORY_CHANGED',
            'DOCUMENT_VERSION_USER_UPLOAD_UPDATE',
            'DOCUMENT_VERSION_USER_ATTACH_DOCUMENT_PAGES',
            'RULE_COULD_NOT_EXECUTE'
          ]::public.document_history_type[],
          false,
          true
      ;
    when 'USER_ACTIVITIES' then
      return query
        select
          array[
          'AUTOMATION_ACTION_ON_DOCUMENT',
          -- legacy
          'RULE_DOCUMENT',
          'RULE_INVOICE',
          'RULE_DOCUMENT_APPROVAL_REQUEST',
          'RULE_CANCEL_DOCUMENT_APPROVAL_REQUEST',
          'RULE_DOCUMENT_MACRO',
          'RULE_COULD_NOT_EXECUTE'
          ]::public.document_history_type[],
          true,
          false
      ;
    when 'APPROVAL_WORKFLOW' then
      return query
        select
          array[
            'COMMENT',
            'APPROVAL_REQUESTED',
            'APPROVAL_FULFILLED',
            'WORKFLOW_STEP'
          ]::public.document_history_type[],
          false,
          false
      ;
    when 'COMMENT' then
      return query select array['COMMENT']::public.document_history_type[], false, false;
    else
      raise exception 'Invalid preset value: %', preset;
  end case;
end;
$$ language plpgsql stable;

----

create view public.document_history as (
  (
    select
      id::text,
      'NOTIFICATION'::public.document_history_type as "type",
      document_id,
      notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from rule.send_notification_log
  ) union all (
    select
      id::text,
      'IMPORTED'::public.document_history_type as "type",
      id as document_id,
      null::uuid as notification_id,

      imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      import_date as created_at
    from public.document
  ) union all (
    select
      export.id::text,
      'EXPORT'::public.document_history_type as "type",
      export_document.document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      export.id         as export_id,
      export.created_by as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      export.created_at as created_at
    from public.export_document
      inner join public.export on export.id = export_document.export_id
    where not export.booking_export
    and not export.ready_for_booking_export
  ) union all (
    select
      export.id::text,
      'BOOKED'::public.document_history_type as "type",
      export_document.document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      export.id         as export_id,
      export.created_by as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      export.created_at as created_at
    from public.export_document
      inner join public.export on export.id = export_document.export_id
    where export.booking_export
  ) union all (
    select
      export.id::text || '-' || export_document.removed_by || '_' || export_document.removed_at,
      'BOOKING_CANCELED'::public.document_history_type as "type",
      export_document.document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      export.id         as export_id,
      export.created_by as exported_by,

      export_document.removed_at as unexported_at,
      export_document.removed_by as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      export_document.removed_at as created_at
    from public.export_document
      inner join public.export on export.id = export_document.export_id
    where export.booking_export
    and export_document.removed_at is not null
  ) union all (
    select
      export.id::text,
      'READY_FOR_BOOKING'::public.document_history_type as "type",
      export_document.document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      export.id         as export_id,
      export.created_by as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      export.created_at as created_at
    from public.export_document
      inner join public.export on export.id = export_document.export_id
    where export.ready_for_booking_export
  ) union all (
    select
      document_comment.id::text,
      'COMMENT'::public.document_history_type as "type",
      document_comment.document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      document_comment.id           as comment_id,
      document_comment.commented_by as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      document_comment.created_at as created_at
    from public.document_comment
    -- skip related comments because they'll appear under the related element in the related_document_comment_id column
    where related_document_approval_request_id is null
    and related_document_approval_id is null
    and related_document_workflow_step_log_id is null
  ) union all (
    select
      id::text,
      'APPROVAL_REQUESTED'::public.document_history_type as "type",
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      id                  as approval_request_id,
      requester_id        as approval_requester_id,
      approver_id         as approval_requested_approver_id, -- null -> "blank" request, anyone can sign
      blank_approver_type as approval_request_blank_approver_type,
      message             as approval_request_message,
      null::uuid          as approver_id,
      null::uuid          as next_approval_request_id,
      null::boolean       as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as commit_user_id,
      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      (select document_comment.id from public.document_comment
      where related_document_approval_request_id = document_approval_request.id) as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from public.document_approval_request
  ) union all (
    select
      document_approval.id::text,
      'APPROVAL_FULFILLED'::public.document_history_type as "type",
      document_approval_request.document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      request_id                            as approval_request_id,
      requester_id                          as approval_requester_id,
      document_approval_request.approver_id as approval_requested_approver_id,
      blank_approver_type                   as approval_request_blank_approver_type,
      document_approval_request.message     as approval_request_message,
      document_approval.approver_id         as approver_id,
      next_request_id                       as next_approval_request_id, -- if not null, is rejected
      canceled                              as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as commit_user_id,
      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      (select document_comment.id from public.document_comment
      where related_document_approval_id = document_approval.id) as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      document_approval.created_at
    from public.document_approval
      inner join public.document_approval_request on document_approval_request.id = document_approval.request_id
  ) union all (
    select
      id::text,
      'WORKFLOW_STEP'::public.document_history_type as "type",
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      user_id as workflow_step_pushed_by,
      prev_id as prev_workflow_step_id,
      next_id as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as commit_user_id,
      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      (select document_comment.id from public.document_comment
      where related_document_workflow_step_log_id = document_workflow_step_log.id) as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from public.document_workflow_step_log
  ) union all (
    select
      id::text,
      'RULE_DOCUMENT'::public.document_history_type as "type",
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from rule.document_log
  ) union all (
    select
      id::text,
      'RULE_INVOICE'::public.document_history_type as "type",
      invoice_document_id as document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from rule.invoice_log
  ) union all (
    select
      id::text,
      'RULE_DOCUMENT_APPROVAL_REQUEST'::public.document_history_type as "type",
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from rule.document_approval_request_log
  ) union all (
    select
      id::text,
      'RULE_CANCEL_DOCUMENT_APPROVAL_REQUEST'::public.document_history_type as "type",
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from rule.cancel_document_approval_request_log
  ) union all (
    select
      id::text,
      'RULE_DOCUMENT_MACRO'::public.document_history_type as "type",
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from rule.document_macro_log
  ) union all (
    select
      id::text,
      'RULE_COULD_NOT_EXECUTE'::public.document_history_type as "type",
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from rule.document_ready
    where attempted_is_ready_true
    -- the rule execution exceptions are verbose and should not be exposed to all users
  ) union all (
    select
      id::text,
      "type"::text::public.document_history_type, -- history type is union of document log type
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      user_id as document_log_user_id,
      review_group_id,

      document_log.share_user_id,

      prev_category_id,
      next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from public.document_log
  )  union all (
    select
      id::text,
      'PAYMENT_REMINDER_SENT'::public.document_history_type as "type",
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      id         as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      created_at
    from public.document_payment_reminder
  ) union all (
    select
      id::text,
      'DOCUMENT_VERSION_USER_UPLOAD_UPDATE'::public.document_history_type as "type",
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      version::created_time as created_at
    from docdb.document_version
    where commit_reason = 'USER_UPLOAD_UPDATE'
  )  union all (
    select
      id::text,
      'DOCUMENT_VERSION_USER_ATTACH_DOCUMENT_PAGES'::public.document_history_type as "type",
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      commit_user_id,

      null::uuid as related_document_comment_id,

      null::uuid as automation_action_on_document_log_id,

      version::created_time as created_at
    from docdb.document_version
    where commit_reason = 'USER_ATTACH_DOCUMENT_PAGES'
  ) union all (
    select
      id::text,
      'AUTOMATION_ACTION_ON_DOCUMENT',
      document_id,
      null::uuid as notification_id,

      null::uuid as imported_by,

      null::uuid as export_id,
      null::uuid as exported_by,

      null::timestamptz as unexported_at,
      null::uuid        as unexported_by,

      null::uuid as comment_id,
      null::uuid as commented_by,

      null::uuid as approval_request_id,
      null::uuid as approval_requester_id,
      null::uuid as approval_requested_approver_id,
      null::public.document_approval_request_blank_approver_type as approval_request_blank_approver_type,
      null       as approval_request_message,
      null::uuid as approver_id,
      null::uuid as next_approval_request_id,
      null::boolean as approval_request_canceled,

      null::uuid as workflow_step_pushed_by,
      null::uuid as prev_workflow_step_id,
      null::uuid as next_workflow_step_id,

      null::uuid as action_reaction_id,

      null::uuid as document_log_user_id,
      null::uuid as review_group_id,

      null::uuid as share_user_id,

      null::uuid as prev_category_id,
      null::uuid as next_category_id,

      null::uuid as payment_reminder_id,

      null::uuid as commit_user_id,

      null::uuid as related_document_comment_id,

      id as automation_action_on_document_log_id,

      created_at
    from automation.action_on_document_log
  )
);

grant select on public.document_history to domonda_user;
grant select on public.document_history to domonda_wg_user;

comment on column public.document_history.id is '@notNull';
comment on column public.document_history."type" is '@notNull';
comment on column public.document_history.document_id is '@notNull';
comment on column public.document_history.approval_request_message is '@deprecated Please use the `relatedDocumentComment` for a related `DocumentComment.message` instead.';
comment on column public.document_history.created_at is '@notNull';
comment on view public.document_history is $$
@primaryKey id
@foreignKey (document_id) references public.document (id)

@foreignKey (imported_by) references public.user (id)

@foreignKey (export_id) references public.export (id)
@foreignKey (exported_by) references public.user (id)
@foreignKey (unexported_by) references public.user (id)

@foreignKey (comment_id) references public.document_comment (id)
@foreignKey (commented_by) references public.user (id)

@foreignKey (approval_request_id) references public.document_approval_request (id)
@foreignKey (approval_requester_id) references public.user (id)
@foreignKey (approval_requested_approver_id) references public.user (id)
@foreignKey (approver_id) references public.user (id)
@foreignKey (next_approval_request_id) references public.document_approval_request (id)

@foreignKey (workflow_step_pushed_by) references public.user (id)
@foreignKey (prev_workflow_step_id) references public.document_workflow_step (id)
@foreignKey (next_workflow_step_id) references public.document_workflow_step (id)

@foreignKey (action_reaction_id) references rule.action_reaction (id)

@foreignKey (document_log_user_id) references public.user (id)
@foreignKey (review_group_id) references public.review_group (id)

@foreignKey (share_user_id) references public.user (id)

@foreignKey (prev_category_id) references public.document_category (id)
@foreignKey (next_category_id) references public.document_category (id)

@foreignKey (payment_reminder_id) references public.document_payment_reminder (id)

@foreignKey (commit_user_id) references public.user (id)

@foreignKey (related_document_comment_id) references public.document_comment (id)

@foreignKey (automation_action_on_document_log_id) references automation.action_on_document_log (id)
Complete `Document` history.$$;

----

create function public.document_history_for_document(
  document_id uuid
) returns setof public.document_history as $$
  select * from public.document_history
  where document_history.document_id = document_history_for_document.document_id
$$ language sql stable;

----

create function public.document_latest_history_for_type(
  document public.document,
  "type"   public.document_history_type
) returns public.document_history as $$
  select * from public.document_history
  where document_history.document_id = document.id
  and document_history."type" = document_latest_history_for_type."type"
  order by created_at desc
  limit 1
$$ language sql stable strict;

----

create function public.document_approval_request_document_history(
  document_approval_request public.document_approval_request
) returns public.document_history as $$
  select * from public.document_history where id = document_approval_request.id::text
$$ language sql stable strict;

comment on function public.document_approval_request_document_history is E'@notNull\nRelated `DocumentHistory` entry for this `DocumentApprovalRequest`.';

----

create function public.document_sorted_history(
  document          public.document,
  types             public.document_history_type[] = null,
  exclude_types     boolean = false,
  exclude_rule_user boolean = false
) returns setof public.document_history as $$
  select * from public.document_history
  where document_history.document_id = document.id
  -- omit duplicate history entries
  -- and case "type"
  --     when 'APPROVAL_REQUESTED' then approval_requester_id <> 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'
  --     when 'WORKFLOW_STEP' then workflow_step_pushed_by <> 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'
  --     else true
  --   end

  -- filter by document history types
  and (
    types is null
    or ("type" = any(types)) = not exclude_types
  )

  -- exclude history entries by the Rule system user (bde919f0-3e23-4bfa-81f1-abff4f45fb51 is the Rule system user)
  and (
    not exclude_rule_user
    or case "type"
      -- bde919f0-3e23-4bfa-81f1-abff4f45fb51 is the Rule system user
      when 'APPROVAL_FULFILLED' then approver_id <> 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'
      when 'WORKFLOW_STEP' then workflow_step_pushed_by <> 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'
      else true
    end
  )

  -- make sure the RLS runs for comments
  and (
    "type" <> 'COMMENT'
    or exists (
      select from public.document_comment
      where document_comment.id = document_history.comment_id
    )
  )
  -- TODO: run RLS for other history types too

  -- WG users cannot see the full history
  -- only when the document arrived, comments mentioning them (see RLS policies) and new version uploads by the user
  and (
    not public.current_user_is_wg()
    or "type" in ('IMPORTED', 'COMMENT')
    or (
      "type" in ('DOCUMENT_VERSION_USER_UPLOAD_UPDATE', 'DOCUMENT_VERSION_USER_ATTACH_DOCUMENT_PAGES')
      and commit_user_id = private.current_user_id()
    )
  )

  order by created_at desc,
    -- logs about rules first (bde919f0-3e23-4bfa-81f1-abff4f45fb51 is the Rule system user)
    commented_by = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'
      or (
        "type" = 'APPROVAL_REQUESTED' and approval_requester_id = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'
      )
      or workflow_step_pushed_by = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51'
      or document_log_user_id = 'bde919f0-3e23-4bfa-81f1-abff4f45fb51',
    -- automation below
    automation_action_on_document_log_id is null,
    -- legacy rules below
    action_reaction_id is null,
    -- comments (or with related comments) on bottom
    coalesce(comment_id, related_document_comment_id) is not null
$$ language sql stable;

----

create function public.document_sorted_history_for_preset(
  document public.document,
  preset   public.document_history_preset
) returns setof public.document_history as $$
  with document_history_preset_filter as (
    select * from public.document_history_preset_filter(preset)
  )
  select document_sorted_history.* from document_history_preset_filter, public.document_sorted_history(
    document,
    document_history_preset_filter.types,
    document_history_preset_filter.exclude_types,
    document_history_preset_filter.exclude_rule_user
  )
$$ language sql stable;

----

create function public.document_history_notification_status(
  history public.document_history
) returns public.notification_status as $$
  select private.status_of_notification(history.notification_id)
$$ language sql stable strict;
