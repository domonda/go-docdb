create view public.current_user_open_document_approval_request_count as (
  select
    document.client_company_id                as client_company_id,
    count(1)                                  as "count",
    min(document_approval_request.created_at) as oldest_document_approval_request_created_at,
    max(document_approval_request.created_at) as newest_document_approval_request_created_at
  from public.document_approval_request
    inner join public.document on document.id = document_approval_request.document_id
  -- not approved or rejected or canceled
  and not exists (select from public.document_approval where document_approval.request_id = document_approval_request.id)
  -- the request fits the current user profile
  and (
    -- direct approval request
    document_approval_request.approver_id = (select private.current_user_id())
    -- user group approval request
    or document_approval_request.user_group_id in (
        select user_group_user.user_group_id from public.user_group_user
        where user_group_user.user_id = (select private.current_user_id())
    )
    -- group approval request, but not from the current user
    or (document_approval_request.blank_approver_type = 'ANYONE'
      and document_approval_request.requester_id <> (select private.current_user_id())
      and exists (select from control.client_company_user
        where client_company_user.client_company_id = document.client_company_id
        and client_company_user.user_id = (select private.current_user_id())
        and client_company_user.role_name <> 'VERIFIER'))
    or (document_approval_request.blank_approver_type = 'ACCOUNTANT'
      and document_approval_request.requester_id <> (select private.current_user_id())
      and exists (select from control.client_company_user
        where client_company_user.client_company_id = document.client_company_id
        and client_company_user.user_id = (select private.current_user_id())
        and client_company_user.role_name = 'ACCOUNTANT'))
    or (document_approval_request.blank_approver_type = 'VERIFIER'
      and document_approval_request.requester_id <> (select private.current_user_id())
      and exists (select from control.client_company_user
        where client_company_user.client_company_id = document.client_company_id
        and client_company_user.user_id = (select private.current_user_id())
        and client_company_user.role_name = 'VERIFIER')))
  -- the approval request should be issued only after the document left the review
  -- not locked by a review group
  -- and not exists (select from public.review_group_document
  --     inner join public.review_group on review_group.id = review_group_document.review_group_id
  -- where review_group_document.source_document_id = document.id
  -- and review_group.documents_lock_id is not null)
  group by
    document.client_company_id
  -- must have at least 1 open approval request
  having count(1) > 0
);

grant select on table public.current_user_open_document_approval_request_count to domonda_user;

comment on column public.current_user_open_document_approval_request_count.client_company_id is '@notNull';
comment on column public.current_user_open_document_approval_request_count.count is '@notNull';
comment on column public.current_user_open_document_approval_request_count.oldest_document_approval_request_created_at is '@notNull';
comment on column public.current_user_open_document_approval_request_count.newest_document_approval_request_created_at is '@notNull';
comment on view public.current_user_open_document_approval_request_count is
$$@primaryKey client_company_id
@foreignKey (client_company_id) references public.client_company (company_id)$$;

----

create function public.unmatched_documents(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.document as $$
    select *
    from public.filter_documents_v2(
        client_company_id=>client_company_id,
        superseded=>false,
        archived=>false,
        date_filter_type=>'INVOICE_DATE',
        from_date=>from_date,
        until_date=>until_date,
        paid_status=>'NOT_PAID'
    )
$$ language sql stable;

create function public.unmatched_money_transactions(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.money_transaction as $$
    select *
    from public.filter_money_transactions_v2(
        client_company_id=>client_company_id,
        from_date=>from_date,
        until_date=>until_date,
        max_matched_count=>0,
        exclude_money_category_ids=>true,
        money_category_ids=>'{}'
    )
$$ language sql stable;

----

create function public.documents_in_workflow_steps_since_days(
    client_company_id uuid,
    "days"            int,
    from_date         date = null,
    until_date        date = null
) returns setof public.document_workflow_step as $$
    select distinct document_workflow_step.*
    -- we dont use public here because the inner join on document_workflow_step will invoke the policies
    from private.filter_documents_v2(
        client_company_id=>client_company_id,
        superseded=>false,
        archived=>false,
        date_filter_type=>'INVOICE_DATE',
        from_date=>from_date,
        until_date=>until_date,
        document_workflow_step_ids=>'{}'
    ) as document
        inner join public.document_workflow_step on document_workflow_step.id = document.workflow_step_id
    and (select
            -- mustnt be the last step (last step means done)
            not public.document_workflow_step_is_last_step(document_workflow_step)
            -- too long in workflow step
            and documents_in_workflow_steps_since_days."days" <= date_part('day', now() - document_workflow_step_log.created_at)
        from public.document_workflow_step_log
            -- only next steps because we want the document in a workflow (if next step is null, there is no workflow)
            inner join public.document_workflow_step on document_workflow_step.id = document_workflow_step_log.next_id
        where document_workflow_step_log.document_id = document.id
        order by document_workflow_step_log.created_at desc -- newest on top
        limit 1) -- interested only in the last move
$$ language sql stable;

----

create function public.documents_in_workflow_steps_are_abandoned(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.document_workflow_step as $$
    select distinct document_workflow_step.*
    -- we dont use public here because the inner join on document_workflow_step will invoke the policies
    from private.filter_documents_v2(
        client_company_id=>client_company_id,
        superseded=>false,
        archived=>false,
        date_filter_type=>'INVOICE_DATE',
        from_date=>from_date,
        until_date=>until_date,
        document_workflow_step_ids=>'{}'
    ) as document
        inner join public.document_workflow_step on document_workflow_step.id = document.workflow_step_id
    -- first step doesn't count as last step if it's the only one
    and not (
        document_workflow_step.index > 1
        and public.document_workflow_step_is_last_step(document_workflow_step)
    -- doesn't have open approval requests to anyone except verifier
    ) and not exists (
        select from public.document_approval_request
        where document_approval_request.document_id = document.id
        and document_approval_request.blank_approver_type <> 'VERIFIER'
        and public.is_document_approval_request_open(document_approval_request.id)
    -- only when setting is enabled for client company
    ) and exists (
        select from public.client_company
        where client_company.company_id = documents_in_workflow_steps_are_abandoned.client_company_id
        and client_company.abandoned_documents_warning
    )
$$ language sql stable;

----

create function public.documents_are_abandoned(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.document as $$
    select document.*
    -- we dont use public here because the inner join on document_workflow_step will invoke the policies
    from private.filter_documents_v2(
        client_company_id=>client_company_id,
        superseded=>false,
        archived=>false,
        date_filter_type=>'INVOICE_DATE',
        from_date=>from_date,
        until_date=>until_date
    ) as document
    where document.workflow_step_id is null
    -- doesn't have open approval requests to anyone except verifier
    and not exists (
        select from public.document_approval_request
        where document_approval_request.document_id = document.id
        and document_approval_request.blank_approver_type <> 'VERIFIER'
        and public.is_document_approval_request_open(document_approval_request.id)
    -- only when setting is enabled for client company
    ) and exists (
        select from public.client_company
        where client_company.company_id = documents_are_abandoned.client_company_id
        and client_company.abandoned_documents_warning
    )
$$ language sql stable;

----

create function public.open_document_approval_requests_for_client_company(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.document_approval_request as $$
    select distinct on (document_approval_request.document_id) document_approval_request.*
    from public.filter_documents_v2(
      client_company_id=>client_company_id,
      superseded=>false,
      archived=>false,
      date_filter_type=>'INVOICE_DATE',
      from_date=>from_date,
      until_date=>until_date,
      is_approved=>false
    ) as document
      inner join public.document_approval_request
      on document_approval_request.document_id = document.id
      and public.is_document_approval_request_open(document_approval_request.id)
$$ language sql stable;

create function public.current_user_open_document_approval_requests_for_client_company(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.document_approval_request as $$
    select document_approval_request.*
    from public.filter_documents_v2(
      client_company_id=>client_company_id,
      superseded=>false,
      archived=>false,
      date_filter_type=>'INVOICE_DATE',
      from_date=>from_date,
      until_date=>until_date,
      is_approved=>false,
      requested_approver_ids=>array[private.current_user_id()]
    ) as document
      inner join public.document_approval_request
      on document_approval_request.document_id = document.id
      -- request must be open
      and not exists (select from public.document_approval where document_approval.request_id = document_approval_request.id)
      -- request is for the current user
      and (document_approval_request.approver_id = (select private.current_user_id())
        -- user group approval request
        or document_approval_request.user_group_id in (
            select user_group_user.user_group_id from public.user_group_user
            where user_group_user.user_id = (select private.current_user_id())
        )
        -- request for anyones approval except verifier and current user
        or (document_approval_request.blank_approver_type = 'ANYONE'
            and document_approval_request.requester_id <> (select private.current_user_id())
            and exists (select from control.client_company_user
                where client_company_user.client_company_id = client_company_id
                and client_company_user.user_id = (select private.current_user_id())
                and client_company_user.role_name <> 'VERIFIER'))
        -- request for a group type approval, but not from current user
        or (document_approval_request.blank_approver_type = 'ACCOUNTANT'
            and document_approval_request.requester_id <> (select private.current_user_id())
            and exists (select from control.client_company_user
                where client_company_user.client_company_id = client_company_id
                and client_company_user.user_id = (select private.current_user_id())
                and client_company_user.role_name = 'ACCOUNTANT'))
        or (document_approval_request.blank_approver_type = 'VERIFIER'
            and document_approval_request.requester_id <> (select private.current_user_id())
            and exists (select from control.client_company_user
                where client_company_user.client_company_id = client_company_id
                and client_company_user.user_id = (select private.current_user_id())
                and client_company_user.role_name = 'VERIFIER')))
$$ language sql stable;

----

create function private.unbooked_documents(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.document as $$
    select document.*
    from public.document
        left join public.invoice on invoice.document_id = document.id
    where document.client_company_id = unbooked_documents.client_company_id
    and not superseded
    and not archived
    and (from_date is null
        or (invoice.invoice_date is not null and invoice.invoice_date >= from_date))
    and (until_date is null
        or (invoice.invoice_date is not null and invoice.invoice_date <= until_date))
    and not exists (select from public.export_document
      where export_document.document_id = document.id
      -- and export_document.removed_at is null as per Stefan, once exported for booking, always booked
      and true in (select export.booking_export from public.export
        where export.id = export_document.export_id))
    -- deprecated document export
    and not exists (select from public.document_export_document as ded
      where ded.document_id = document.id
      and true in (select de.booking_export from public.document_export as de
        where de.id = ded.document_export_id))
$$ language sql stable security definer;

create function public.unbooked_documents(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.document as $$
    select document.* from private.unbooked_documents(client_company_id, from_date, until_date)
        inner join public.document on document.id = unbooked_documents.id
$$ language sql stable;

----

create function private.invoices_without_accounting_items(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.invoice as $$
    -- using a CTE forces proper invoice filter plan and then check for boost in performance
    with invoice as materialized (
        select invoice.*
        from public.invoice
            inner join public.document on document.id = invoice.document_id
        where document.client_company_id = invoices_without_accounting_items.client_company_id
        and not superseded
        and not archived
        and (from_date is null
            or (invoice.invoice_date >= from_date))
        and (until_date is null
            or (invoice.invoice_date <= until_date))
    )
    select * from invoice
    -- doesnt have accounting items
    where not exists (select from public.invoice_accounting_item where invoice_accounting_item.invoice_document_id = invoice.document_id)
    -- or has incomplete accounting items
        or private.calc_remaining_invoice_accounting_item_amount(invoice.document_id) is distinct from 0
$$ language sql stable security definer;

create function public.invoices_without_accounting_items(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.invoice as $$
    select invoice.*
    from private.invoices_without_accounting_items(client_company_id, from_date, until_date) as invoice
        inner join public.document on document.id = invoice.document_id
$$ language sql stable;

----

create function public.money_accounts_sync_older_than_days(
    client_company_id uuid,
    "days"            int
) returns setof public.money_account as $$
    select money_account.*
    from public.money_account
        -- interested in connected accounts only
        inner join (xs2a.account
            -- left join because the account might not have an active connection
            left join xs2a."connection" on "connection".id = account.connection_id)
        on account.id = money_account.xs2a_account_id
    where money_account.client_company_id = money_accounts_sync_older_than_days.client_company_id
    and money_account.active
    and ("connection" is null
        or money_accounts_sync_older_than_days."days" <= date_part('day', now() - "connection".last_synced))
$$ language sql stable strict security definer;

----

create function public.money_accounts_imports_older_than_days(
    client_company_id uuid,
    "days"            int
) returns setof public.money_account as $$
    select money_account.*
    from public.money_account
        inner join lateral (
            -- TODO: joining the document kills performance
            select
                created_at as import_date
                -- document.import_date
            from public.money_transaction
                -- inner join public.document
                -- on document.id = money_transaction.import_document_id
            where money_transaction.account_id = money_account.id
            order by created_at desc
            -- order by document.import_date desc
            limit 1
        ) as newest_transaction
        on true
    where money_account.client_company_id = money_accounts_imports_older_than_days.client_company_id
    and money_account.active
    and money_account.xs2a_account_id is null
    -- cash accounts dont need imports
    and not exists (
        select from public.cash_account
        where cash_account.id = money_account.id
    )
    and date_part('day', now() - newest_transaction.import_date) >= money_accounts_imports_older_than_days."days"
$$ language sql stable strict security definer;

----

-- duplicates accounts for both the invoice and its duplicate
create function public.duplicate_invoices(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns setof public.invoice as $$
    select invoice.*
    from public.filter_documents_v2(
        client_company_id=>client_company_id,
        superseded=>false,
        archived=>false,
        date_filter_type=>'INVOICE_DATE',
        from_date=>from_date,
        until_date=>until_date,
        is_duplicate=>true
    ) as document
        inner join public.invoice on invoice.document_id = document.id
$$ language sql stable;

----

create function public.due_or_overdue_incoming_invoices(
    client_company_id uuid
) returns setof public.invoice as $$
    select invoice.*
    from public.filter_documents_v2(
        client_company_id=>client_company_id,
        superseded=>false,
        archived=>false,
        document_types=>'{INCOMING_INVOICE}',
        date_filter_type=>'DUE_DATE',
        until_date=>current_date,
        paid_status=>'NOT_PAID'
    ) as document
        inner join public.invoice on invoice.document_id = document.id
$$ language sql stable strict;

create function public.overdue_outgoing_invoices(
    client_company_id uuid
) returns setof public.invoice as $$
    select invoice.*
    from public.filter_documents_v2(
        client_company_id=>client_company_id,
        superseded=>false,
        archived=>false,
        document_types=>'{OUTGOING_INVOICE}',
        date_filter_type=>'DUE_DATE',
        until_date=>(current_date - interval '1 day')::date,
        paid_status=>'NOT_PAID'
    ) as document
        inner join public.invoice on invoice.document_id = document.id
$$ language sql stable strict;

----

create function public.ready_review_groups_older_than_days(
    client_company_id uuid,
    "days"            int
) returns setof public.review_group as $$
    select * from public.review_group
    where client_company_id = ready_review_groups_older_than_days.client_company_id
    and public.review_group_status(review_group) = 'READY'
    and ready_review_groups_older_than_days."days" <= date_part('day', now() - review_group.created_at)
    and exists (select from public.review_group_document where review_group_document.review_group_id = review_group.id)
    order by created_at asc -- oldest on top
$$ language sql stable strict;

----

create function public.unseen_comment_mentions_for_current_user_in_client_company(
    client_company_id uuid
) returns setof public.document_comment as $$
    select document_comment.* from public.document_comment
        inner join public.document on document.id = document_comment.document_id
    where document.client_company_id = unseen_comment_mentions_for_current_user_in_client_company.client_company_id
    and (select private.current_user_id()) in (select * from unnest(public.document_comment_message_mentioned_user_ids(document_comment.message)))
    -- own comments don't have seen states, they're considered seen already
    and document_comment.commented_by <> (select private.current_user_id())
    and not exists (select from public.document_comment_seen
        where document_comment_seen.document_comment_id = document_comment.id
        and document_comment_seen.seen_by = (select private.current_user_id()))
$$ language sql stable strict;

----

-- aggregates all ranged todos and checks if there are any
-- if no from/until dates are provided, check is there is any ranged at all
create function public.any_todo_for_client_company(
    client_company_id uuid,
    from_date         date = null,
    until_date        date = null
) returns boolean as $$
    select exists (select from public.unmatched_money_transactions(client_company_id, from_date, until_date))
    or exists (select from public.open_document_approval_requests_for_client_company(client_company_id, from_date, until_date))
    or exists (select from public.current_user_open_document_approval_requests_for_client_company(client_company_id, from_date, until_date))
    or exists (select from public.unbooked_documents(client_company_id, from_date, until_date))
    or exists (select from public.invoices_without_accounting_items(client_company_id, from_date, until_date))
    or exists (select from public.duplicate_invoices(client_company_id, from_date, until_date))
$$ language sql stable;
comment on function public.any_todo_for_client_company is
E'@notNull\nChecks if there are any ranged TODOs. If no range is given, checks for any ranged TODOs at all.';

----

-- TODO-db-210325 any todos for all accessable clients

