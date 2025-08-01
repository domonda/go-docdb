create type public.activity_log_type as enum (
  -- public.user_activity_log_type
  'LOGIN',
  'LOGOUT',
  'CURRENT_CLIENT_COMPANY_CHANGE', -- deprecated
  -- ./public.user_activity_log_type
  'IMPORTED_DOCUMENTS',
  'APPROVED',
  'WORKFLOW_STEP_CHANGED',
  'IMPORTED_MONEY_TRANSACTIONS',
  'COMMENTED',
  'AUTO_MATCHED_TRANSACTIONS',
  'READY_FOR_BOOKING_DOCUMENTS',
  'BOOKED_DOCUMENTS',
  'EXPORTED_DOCUMENTS'
);

create type public.activity_log as (
  "type" public.activity_log_type,

  client_company_id uuid,
  user_id           uuid,

  next_workflow_step_id uuid,

  documents_count          int,
  money_transactions_count int,

  document_ids uuid[],
  money_transaction_ids uuid[],

  export_id uuid,

  created_at timestamptz
);

comment on column public.activity_log."type" is '@notNull';
comment on column public.activity_log.created_at is '@notNull';
comment on type public.activity_log is $$
@foreignKey (client_company_id) references public.client_company (company_id)
@foreignKey (user_id) references public.user (id)
@foreignKey (next_workflow_step_id) references public.document_workflow_step (id)
@foreignKey (export_id) references public.export (id)$$;

create function public.filter_activity_logs(
  client_company_id uuid,
  from_date         date,
  until_date        date = null
) returns setof public.activity_log as $$
  select activity_log.* from ((
      -- user activity
      select
        user_activity_log."type"::text::public.activity_log_type,
        (user_activity_log.payload->>'clientCompanyId')::uuid as client_company_id,
        user_id,
        null::uuid as next_workflow_step_id,
        null::int as documents_count,
        null::int as money_transactions_count,
        null::uuid[] as document_ids,
        null::uuid[] as money_transaction_ids,
        null::uuid as export_id,
        user_activity_log.created_at
      from public.user_activity_log
        inner join public.user on "user".id = user_activity_log.user_id
      where user_activity_log.user_id <> (select private.current_user_id())
      and filter_activity_logs.from_date >= user_activity_log.created_at
      and (filter_activity_logs.until_date is null
        or filter_activity_logs.until_date <= user_activity_log.created_at)
      -- has access to the company user belongs to
      and exists (select from control.client_company_user
        where client_company_user.user_id = (select private.current_user_id())
        and client_company_user.client_company_id = "user".client_company_id)
    ) union all (
      -- X uploaded N documents (per day)
      select
        'IMPORTED_DOCUMENTS'::public.activity_log_type as "type",
        document.client_company_id,
        imported_by as user_id,
        null::uuid as next_workflow_step_id,
        count(1)::int as documents_count,
        null::int as money_transactions_count,
        array_agg(document.id)::uuid[] as document_ids,
        null::uuid[] as money_transaction_ids,
        null::uuid as export_id,
        max(import_date) as created_at
      from public.document
      where document.client_company_id = filter_activity_logs.client_company_id
      -- document has pages and is therefore visual
      and document.num_pages > 0
      -- not locked by a review group
      and not exists (select from public.review_group_document
        inner join public.review_group on review_group.id = review_group_document.review_group_id
      where review_group_document.source_document_id = document.id
      and review_group.documents_lock_id is not null)
      and import_date >= filter_activity_logs.from_date
      and (filter_activity_logs.until_date is null
        or import_date <= filter_activity_logs.until_date)
      group by document.client_company_id, imported_by, import_date::date
    ) union all (
      -- X approved N documents (per day)
      select
        'APPROVED'::public.activity_log_type as "type",
        document.client_company_id,
        document_approval.approver_id as user_id,
        null::uuid as next_workflow_step_id,
        count(distinct document_approval_request.document_id)::int as documents_count,
        null::int as money_transactions_count,
        array_agg(distinct document_approval_request.document_id)::uuid[] as document_ids,
        null::uuid[] as money_transaction_ids,
        null::uuid as export_id,
        max(document_approval.created_at) as created_at
      from public.document_approval
        inner join (public.document_approval_request
          inner join public.document on document.id = document_approval_request.document_id)
        on document_approval_request.id = document_approval.request_id
      where document.client_company_id = filter_activity_logs.client_company_id
      and document_approval.next_request_id is null -- exclude rejections
      and not document_approval.canceled -- exclude cancellations
      and document_approval.created_at >= filter_activity_logs.from_date
      and (filter_activity_logs.until_date is null
        or document_approval.created_at <= filter_activity_logs.until_date)
      group by document.client_company_id, document_approval.approver_id, document_approval.created_at::date
    ) union all (
      -- X pushed N documents to Y (workflow) (per day)
      select
        'WORKFLOW_STEP_CHANGED'::public.activity_log_type as "type",
        document.client_company_id,
        document_workflow_step_log.user_id,
        document_workflow_step_log.next_id as next_workflow_step_id,
        count(distinct document_workflow_step_log.document_id)::int as documents_count,
        null::int as money_transactions_count,
        array_agg(distinct document_workflow_step_log.document_id)::uuid[] as document_ids,
        null::uuid[] as money_transaction_ids,
        null::uuid as export_id,
        max(document_workflow_step_log.created_at) as created_at
      from public.document_workflow_step_log
        inner join public.document on document.id = document_workflow_step_log.document_id
      where document.client_company_id = filter_activity_logs.client_company_id
      and document_workflow_step_log.created_at >= filter_activity_logs.from_date
      and (filter_activity_logs.until_date is null
        or document_workflow_step_log.created_at <= filter_activity_logs.until_date)
      group by document.client_company_id, document_workflow_step_log.user_id, document_workflow_step_log.next_id, document_workflow_step_log.created_at::date
    ) union all (
      -- N new transactions (per day)
      select
        'IMPORTED_MONEY_TRANSACTIONS'::public.activity_log_type as "type",
        money_account.client_company_id,
        null::uuid as user_id,
        null::uuid as next_workflow_step_id,
        null::int as documents_count,
        count(1)::int as money_transactions_count,
        null::uuid[] as document_ids,
        array_agg(money_transaction.id)::uuid[] as money_transaction_ids,
        null::uuid as export_id,
        max(money_transaction.created_at) as created_at
      from public.money_transaction
        inner join public.money_account on money_account.id = money_transaction.account_id
      where money_account.client_company_id = filter_activity_logs.client_company_id
      and money_transaction.created_at >= filter_activity_logs.from_date
      and (filter_activity_logs.until_date is null
        or money_transaction.created_at <= filter_activity_logs.until_date)
      group by money_account.client_company_id, money_transaction.created_at::date
    ) union all (
      -- X commented on N documents (per day)
      select
        'COMMENTED'::public.activity_log_type as "type",
        document.client_company_id,
        commented_by as user_id,
        null::uuid as next_workflow_step_id,
        count(distinct document_comment.document_id)::int as documents_count,
        null::int as money_transactions_count,
        array_agg(distinct document_comment.document_id)::uuid[] as document_ids,
        null::uuid[] as money_transaction_ids,
        null::uuid as export_id,
        max(document_comment.created_at) as created_at
      from public.document_comment
        inner join public.document on document.id = document_comment.document_id
      where document.client_company_id = filter_activity_logs.client_company_id
      and document_comment.created_at >= filter_activity_logs.from_date
      and (filter_activity_logs.until_date is null
        or document_comment.created_at <= filter_activity_logs.until_date)
      group by document.client_company_id, commented_by, document_comment.created_at::date
    ) union all (
      -- N transactions matched automatically (per day)
      select
        'AUTO_MATCHED_TRANSACTIONS'::public.activity_log_type as "type",
        document.client_company_id,
        null::uuid as user_id,
        null::uuid as next_workflow_step_id,
        null::int as documents_count,
        count(distinct document_money_transaction.money_transaction_id)::int as money_transactions_count,
        null::uuid[] as document_ids,
        array_agg(distinct document_money_transaction.money_transaction_id)::uuid[] as money_transaction_ids,
        null::uuid as export_id,
        max(document_money_transaction.created_at) as created_at
      from public.document_money_transaction
        inner join public.document on document.id = document_money_transaction.document_id
      where document.client_company_id = filter_activity_logs.client_company_id
      and document_money_transaction.created_at >= filter_activity_logs.from_date
      and (filter_activity_logs.until_date is null
        or document_money_transaction.created_at <= filter_activity_logs.until_date)
      group by document.client_company_id, document_money_transaction.created_at::date
    ) union all (
      -- X sent N documents to accounting (per day as in "when it happened?")
      select
        'READY_FOR_BOOKING_DOCUMENTS'::public.activity_log_type as "type",
        export.client_company_id,
        export.created_by as user_id,
        null::uuid as next_workflow_step_id,
        count(distinct export_document.document_version_id)::int as documents_count,
        null::int as money_transactions_count,
        array_agg(distinct export_document.document_id)::uuid[] as document_ids,
        null::uuid[] as money_transaction_ids,
        export.id as export_id,
        max(export.created_at) as created_at
      from public.export_document
        inner join public.export on export.id = export_document.export_id
      where export.client_company_id = filter_activity_logs.client_company_id
      and export.ready_for_booking_export
      and export.created_at >= filter_activity_logs.from_date
      and (filter_activity_logs.until_date is null
        or export.created_at <= filter_activity_logs.until_date)
      group by export.client_company_id, export.created_by, export.id, export.created_at::date
    ) union all (
      -- X booked N documents (per day)
      select
        'BOOKED_DOCUMENTS'::public.activity_log_type as "type",
        export.client_company_id,
        export.created_by as user_id,
        null::uuid as next_workflow_step_id,
        count(distinct export_document.document_version_id)::int as documents_count,
        null::int as money_transactions_count,
        array_agg(distinct export_document.document_id)::uuid[] as document_ids,
        null::uuid[] as money_transaction_ids,
        export.id as export_id,
        max(export.created_at) as created_at
      from public.export_document
        inner join public.export on export.id = export_document.export_id
      where export.client_company_id = filter_activity_logs.client_company_id
      and export.booking_export
      and export.created_at >= filter_activity_logs.from_date
      and (filter_activity_logs.until_date is null
        or export.created_at <= filter_activity_logs.until_date)
      group by export.client_company_id, export.created_by, export.id, export.created_at::date
    ) union all (
      -- X exported N documents (per day)
      select
        'EXPORTED_DOCUMENTS'::public.activity_log_type as "type",
        export.client_company_id,
        export.created_by as user_id,
        null::uuid as next_workflow_step_id,
        count(distinct export_document.document_version_id)::int as documents_count,
        null::int as money_transactions_count,
        array_agg(distinct export_document.document_id)::uuid[] as document_ids,
        null::uuid[] as money_transaction_ids,
        export.id as export_id,
        max(export.created_at) as created_at
      from public.export_document
        inner join public.export on export.id = export_document.export_id
      where export.client_company_id = filter_activity_logs.client_company_id
      and not export.booking_export
      and not export.ready_for_booking_export
      and export.created_at >= filter_activity_logs.from_date
      and (filter_activity_logs.until_date is null
        or export.created_at <= filter_activity_logs.until_date)
      group by export.client_company_id, export.created_by, export.id, export.created_at::date
  )) as activity_log
  order by activity_log.created_at desc
$$ language sql stable;
