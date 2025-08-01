create function api.filter_documents(
    -- fulltext
    search_text text = '',
    -- superseded
    -- superseded boolean = null, -- Never show superseded docs in API? See api.document
    -- archived
    archived boolean = null,
    -- has_warning
    has_warning boolean = null,
    -- internal number
    internal_number text = null,
    -- date
    date_filter_type public.filter_documents_date_filter_type = 'INVOICE_DATE',
    from_date        date = null,
    until_date       date = null,
    -- totals
    min_total float8 = null,
    max_total float8 = null,
    -- export
    export_status public.filter_documents_export_status = null,
    -- paid_status
    paid_status public.filter_documents_paid_status = null,
    -- document_type
    exclude_document_types boolean = false,
    document_types         public.document_type[] = '{}',
    -- document_category
    exclude_document_category_ids boolean = false,
    document_category_ids         uuid[] = '{}',
    -- partner_company
    exclude_partner_company_ids boolean = false,
    partner_company_ids         uuid[] = null,
    -- client_company_tag
    exclude_client_company_tag_ids boolean = false,
    client_company_tag_ids         uuid[] = null,
    -- cost_center
    exclude_client_company_cost_center_ids boolean = false,
    client_company_cost_center_ids         uuid[] = null,
    -- cost_unit
    exclude_client_company_cost_unit_ids boolean = false,
    client_company_cost_unit_ids         uuid[] = null,
    -- general_ledger_account
    exclude_general_ledger_account_ids boolean = false,
    general_ledger_account_ids         uuid[] = NULL,
    -- workflow
    exclude_document_workflow_step_ids boolean = false,
    document_workflow_step_ids         uuid[] = null,
    -- credit_memos
    is_credit_memo boolean = null,
    -- pain001
    has_pain001_payment boolean = null,
    -- pain008
    has_pain008_direct_debit boolean = NULL,
    -- payment_reminder
    is_payment_reminder_sent boolean = null,
    -- release
    is_approved            boolean = null, -- NOTE: when used in conjunction with `requested_approver_ids` then `is_approved` actually means "is the approval of the requested approver closed"
    requested_approver_ids uuid[] = '{}',
    -- completeness
    exclude_invoice_completeness_details boolean = false,
    invoice_completeness_details         public.invoice_completeness_detail[] = null,
    -- duplicates
    is_duplicate boolean = null,
    -- comments
    has_comments boolean = NULL,
    -- mentions
    comment_mentioned_user_id_is_seen boolean = null,
    comment_mentioned_user_id         uuid = null,
    -- money account
    money_account_ids uuid[] = null,
    -- derived/recurring documents
    base_document_ids uuid[] = '{}',
    is_recurring boolean = null,
    -- contract type
    contract_type public.other_document_contract_type = null,
    -- document_real_estate_object
    exclude_document_real_estate_object_instance_ids boolean = false,
    document_real_estate_object_instance_ids         uuid[] = NULL,
    -- order_bys
    order_bys public.filter_documents_order_by[] = '{}'
) returns setof api.document as
$$
    select
        d.id,
        d.title,
        d.category_id,
        d.client_company_id,
        d.base_document_id,
        d.name,
        d.language,
        d.version,
        d.num_pages,
        d.num_attach_pages,
        d.workflow_step_id,
        d.imported_by,
        d.import_date AS imported_at,
        d.rearranged_at,
        d.rearranged_by,
        d.pages_confirmed_at,
        d.pages_confirmed_by,
        d.checkout_user_id,
        d.checkout_reason,
        d.checkout_time,
        d.updated_at,
        d.created_at,
        (
            SELECT array_agg(cct.name order by cct.name)
            FROM public.document_tag AS dt
                INNER JOIN api.client_company_tag AS cct ON (cct.id = dt.client_company_tag_id)
            WHERE dt.document_id = d.id
        ) as tags
    from private.filter_documents_v2(
        api.current_client_company_id(),
        false, -- exclude_document_ids
        null, -- document_ids
        search_text,
        false, -- superseded
        archived,
        has_warning,
        internal_number,
        date_filter_type,
        from_date,
        until_date,
        min_total,
        max_total,
        export_status,
        paid_status,
        exclude_document_types,
        document_types,
        exclude_document_category_ids,
        document_category_ids,
        exclude_partner_company_ids,
        partner_company_ids,
        exclude_client_company_tag_ids,
        client_company_tag_ids,
        exclude_client_company_cost_center_ids,
        client_company_cost_center_ids,
        exclude_client_company_cost_unit_ids,
        client_company_cost_unit_ids,
        exclude_general_ledger_account_ids,
        general_ledger_account_ids,
        exclude_document_workflow_step_ids,
        document_workflow_step_ids,
        is_credit_memo,
        has_pain001_payment,
        has_pain008_direct_debit,
        is_payment_reminder_sent,
        is_approved,
        requested_approver_ids,
        exclude_invoice_completeness_details,
        invoice_completeness_details,
        is_duplicate,
        has_comments,
        comment_mentioned_user_id_is_seen,
        comment_mentioned_user_id,
        money_account_ids,
        base_document_ids,
        is_recurring,
        contract_type,
        exclude_document_real_estate_object_instance_ids,
        document_real_estate_object_instance_ids,
        order_bys
    ) as d
$$
language sql stable security definer; -- is ok because we lock the client_company argument

----

create type api.filter_documents_statistics_result as (
    incoming_total_sum float8,
    incoming_net_sum   float8,
    outgoing_total_sum float8,
    outgoing_net_sum   float8
);

comment on column api.filter_documents_statistics_result.incoming_total_sum is '@notNull';
comment on column api.filter_documents_statistics_result.outgoing_total_sum is '@notNull';
comment on column api.filter_documents_statistics_result.incoming_net_sum is '@notNull';
comment on column api.filter_documents_statistics_result.outgoing_net_sum is '@notNull';

create function api.filter_documents_statistics(
    -- fulltext
    search_text text = '',
    -- superseded
    -- superseded boolean = null,
    -- archived
    archived boolean = null,
    -- has_warning
    has_warning boolean = null,
    -- internal number
    internal_number text = null,
    -- date
    date_filter_type public.filter_documents_date_filter_type = 'INVOICE_DATE',
    from_date        date = null,
    until_date       date = null,
    -- totals
    min_total float8 = null,
    max_total float8 = null,
    -- export
    export_status public.filter_documents_export_status = null,
    -- paid_status
    paid_status public.filter_documents_paid_status = null,
    -- document_type
    exclude_document_types boolean = false,
    document_types         public.document_type[] = '{}',
    -- document_category
    exclude_document_category_ids boolean = false,
    document_category_ids         uuid[] = '{}',
    -- partner_company
    exclude_partner_company_ids boolean = false,
    partner_company_ids         uuid[] = null,
    -- client_company_tag
    exclude_client_company_tag_ids boolean = false,
    client_company_tag_ids         uuid[] = null,
    -- cost_center
    exclude_client_company_cost_center_ids boolean = false,
    client_company_cost_center_ids         uuid[] = null,
    -- cost_unit
    exclude_client_company_cost_unit_ids boolean = false,
    client_company_cost_unit_ids         uuid[] = null,
    -- general_ledger_account
    exclude_general_ledger_account_ids boolean = false,
    general_ledger_account_ids         uuid[] = NULL,
    -- workflowupdat
    exclude_document_workflow_step_ids boolean = false,
    document_workflow_step_ids         uuid[] = null,
    -- credit_memos
    is_credit_memo boolean = null,
    -- pain001
    has_pain001_payment boolean = null,
    -- pain008
    has_pain008_direct_debit boolean = NULL,
    -- payment_reminder
    is_payment_reminder_sent boolean = null,
    -- release
    is_approved            boolean = null, -- NOTE: when used in conjunction with `requested_approver_ids` then `is_approved` actually means "is the approval of the requested approver closed"
    requested_approver_ids uuid[] = '{}',
    -- completeness
    exclude_invoice_completeness_details boolean = false,
    invoice_completeness_details         public.invoice_completeness_detail[] = null,
    -- duplicates
    is_duplicate boolean = null,
    -- comments
    has_comments boolean = NULL,
    -- mentions
    comment_mentioned_user_id_is_seen boolean = null,
    comment_mentioned_user_id         uuid = null,
    -- money account
    money_account_ids uuid[] = null,
    -- derived/recurring documents
    base_document_ids uuid[] = '{}',
    is_recurring boolean = null,
    -- contract type
    contract_type public.other_document_contract_type = null,
    -- document_real_estate_object
    exclude_document_real_estate_object_instance_ids boolean = false,
    document_real_estate_object_instance_ids         uuid[] = NULL,
    -- order_bys
    order_bys public.filter_documents_order_by[] = '{}'
) returns api.filter_documents_statistics_result as
$$
    select
        coalesce(
            sum(
                case
                    when (
                        (
                            (dc.document_type = 'OUTGOING_INVOICE') and (not i.credit_memo)
                        ) or (
                            (dc.document_type = 'INCOMING_INVOICE') and (i.credit_memo)
                        )
                    ) then coalesce(abs(i.total) / coalesce(i.conversion_rate, 1), 0.0)
                    else 0
                end
            ),
            0
        ) as incoming_total_sum,
        coalesce(
            sum(
                case
                    when (
                        (
                            (dc.document_type = 'OUTGOING_INVOICE') and (not i.credit_memo)
                        ) or (
                            (dc.document_type = 'INCOMING_INVOICE') and (i.credit_memo)
                        )
                    ) then coalesce(abs(i.net) / coalesce(i.conversion_rate, 1), 0.0)
                    else 0
                end
            ),
            0
        ) as incoming_net_sum,
        coalesce(
            sum(
                case
                    when (
                        (
                            (dc.document_type = 'INCOMING_INVOICE') and (not i.credit_memo)
                        ) or (
                            (dc.document_type = 'OUTGOING_INVOICE') and (i.credit_memo)
                        )
                    ) then coalesce(abs(i.total) / coalesce(i.conversion_rate, 1), 0.0)
                    else 0
                end
            ),
            0
        ) as outgoing_total_sum,
        coalesce(
            sum(
                case
                    when (
                        (
                            (dc.document_type = 'INCOMING_INVOICE') and (not i.credit_memo)
                        ) or (
                            (dc.document_type = 'OUTGOING_INVOICE') and (i.credit_memo)
                        )
                    ) then coalesce(abs(i.net) / coalesce(i.conversion_rate, 1), 0.0)
                    else 0
                end
            ),
            0
        ) as outgoing_net_sum
    from api.filter_documents(
        search_text,
        -- superseded,
        archived,
        has_warning,
        internal_number,
        date_filter_type,
        from_date,
        until_date,
        min_total,
        max_total,
        export_status,
        paid_status,
        exclude_document_types,
        document_types,
        exclude_document_category_ids,
        document_category_ids,
        exclude_partner_company_ids,
        partner_company_ids,
        exclude_client_company_tag_ids,
        client_company_tag_ids,
        exclude_client_company_cost_center_ids,
        client_company_cost_center_ids,
        exclude_client_company_cost_unit_ids,
        client_company_cost_unit_ids,
        exclude_general_ledger_account_ids,
        general_ledger_account_ids,
        exclude_document_workflow_step_ids,
        document_workflow_step_ids,
        is_credit_memo,
        has_pain001_payment,
        has_pain008_direct_debit,
        is_payment_reminder_sent,
        is_approved,
        requested_approver_ids,
        exclude_invoice_completeness_details,
        invoice_completeness_details,
        is_duplicate,
        has_comments,
        comment_mentioned_user_id_is_seen,
        comment_mentioned_user_id,
        money_account_ids,
        base_document_ids,
        is_recurring,
        contract_type,
        exclude_document_real_estate_object_instance_ids,
        document_real_estate_object_instance_ids,
        order_bys
    ) as d
        inner join public.invoice as i on i.document_id = d.id
        inner join public.document_category as dc on dc.id = d.category_id
$$
language sql stable;

comment on function api.filter_documents_statistics is '@notNull';
