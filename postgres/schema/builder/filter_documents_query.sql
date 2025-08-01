CREATE TYPE public.filter_documents_date_filter_type AS ENUM (
  'DOCUMENT_DATE', -- figures out the first available, relevant, date to filter by
  'INVOICE_DATE',
  'IMPORT_DATE',
  'DUE_DATE',
  'DISCOUNT_DUE_DATE',
  'PAID_DATE',
  'DELIVERED_DATE'
);

CREATE TYPE public.filter_documents_paid_status AS ENUM (
    'NOT_PAYABLE',
    'NOT_PAID',
    'PARTIALLY_PAID',
    'PAID',
    'PAID_WITH_CREDITCARD',
    'PAID_WITH_CASH',
    'PAID_WITH_MONEY_ACCOUNT',
    'EXPENSES_PAID',
    'PAID_WITH_BANK',
    'PAID_WITH_PAYPAL',
    'PAID_WITH_TRANSFERWISE',
    'PAID_WITH_DIRECT_DEBIT'
);

CREATE TYPE public.filter_documents_export_status AS ENUM (
    'NOT_EXPORTED',
    'EXPORTED',
    'NOT_EXPORTED_FOR_BOOKING',
    'EXPORTED_FOR_BOOKING',
    'NOT_EXPORTED_FOR_READY_FOR_BOOKING',
    'EXPORTED_FOR_READY_FOR_BOOKING',
    -- Depracted (enum values can't be removed from a running DB):
    'NOT_EXPORTED_IN_ABACUS',
    'EXPORTED_IN_ABACUS'
);

CREATE TYPE public.filter_documents_order_by AS ENUM (
  'DOCUMENT_DATE_ASC', -- figures out the first available, relevant, date to sort by
  'DOCUMENT_DATE_DESC',
  'IMPORT_DATE_ASC',
  'IMPORT_DATE_DESC',
  'INVOICE_DATE_ASC',
  'INVOICE_DATE_DESC',
  'DUE_DATE_ASC',
  'DUE_DATE_DESC',
  'DISCOUNT_DUE_DATE_ASC',
  'DISCOUNT_DUE_DATE_DESC',
  'PAID_DATE_ASC',
  'PAID_DATE_DESC',
  'TOTAL_ASC',
  'TOTAL_DESC',
  'PARTNER_COMPANY_ASC',
  'PARTNER_COMPANY_DESC',
  'INVOICE_NUMBER_ASC',
  'INVOICE_NUMBER_DESC',
  'GENERAL_LEDGER_ACCOUNT_ASC',
  'GENERAL_LEDGER_ACCOUNT_DESC',
  'REAL_ESTATE_OBJECT_ASC',
  'REAL_ESTATE_OBJECT_DESC'
);

-- NOTE: filters which allow empty arrays allow for filtering by any of the type:
    -- {} and not exclude     => docs with any of the specified type
    -- {} and exclude         => docs without any of the specified type
    -- {some} and not exclude => docs with some of the specified type
    -- {some} and exclude     => docs without some of the specified type
CREATE FUNCTION builder.filter_documents_query(
    -- required
    client_company_id uuid,
    -- subset of filterable documents
    exclude_document_ids boolean = false,
    document_ids         uuid[] = '{}',
    -- fulltext
    search_text text = '',
    -- superseded
    superseded boolean = NULL,
    -- archived
    archived boolean = NULL,
    -- has_warning
    has_warning boolean = NULL,
    -- internal number
    internal_number text = NULL,
    -- date
    date_filter_type public.filter_documents_date_filter_type = 'INVOICE_DATE',
    from_date        date = NULL,
    until_date       date = NULL,
    -- totals
    min_total float8 = NULL,
    max_total float8 = NULL,
    -- export
    export_status public.filter_documents_export_status = NULL,
    -- paid_status
    paid_status public.filter_documents_paid_status = NULL,
    -- document_type
    exclude_document_types boolean = false,
    document_types         public.document_type[] = '{}',
    -- document_category
    exclude_document_category_ids boolean = false,
    document_category_ids         uuid[] = '{}',
    -- partner_company
    exclude_partner_company_ids boolean = false,
    partner_company_ids         uuid[] = NULL,
    -- client_company_tag
    exclude_client_company_tag_ids boolean = false,
    client_company_tag_ids         uuid[] = NULL,
    -- cost_center
    exclude_client_company_cost_center_ids boolean = false,
    client_company_cost_center_ids         uuid[] = NULL,
    -- cost_unit
    exclude_client_company_cost_unit_ids boolean = false,
    client_company_cost_unit_ids         uuid[] = NULL,
    -- general_ledger_account
    exclude_general_ledger_account_ids boolean = false,
    general_ledger_account_ids         uuid[] = NULL,
    -- workflow
    exclude_document_workflow_step_ids boolean = false,
    document_workflow_step_ids         uuid[] = NULL,
    -- credit_memos
    is_credit_memo boolean = NULL,
    -- pain001
    has_pain001_payment boolean = NULL,
    -- pain008
    has_pain008_direct_debit boolean = NULL,
    -- payment reminder
    is_payment_reminder_sent boolean = NULL,
    -- approval
    is_approved            boolean = NULL, -- NOTE: when used in conjunction with `requested_approver_ids` then `is_approved` actually means "is the approval of the requested approver closed"
    requested_approver_ids uuid[] = '{}',
    -- completeness
    exclude_invoice_completeness_details boolean = false,
    invoice_completeness_details         public.invoice_completeness_detail[] = NULL,
    -- duplicates
    is_duplicate boolean = NULL,
    -- comments
    has_comments boolean = NULL,
    -- mentions
    comment_mentioned_user_id_is_seen boolean = null,
    comment_mentioned_user_id         uuid = null,
    -- money account
    money_account_ids uuid[] = NULL,
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
) RETURNS text AS
$$
DECLARE
    -- filter
    has_document_ids                   boolean := ARRAY_LENGTH(document_ids, 1) IS NOT NULL;
    has_search_text                    boolean := TRIM(search_text) <> '';
    has_superseded                     boolean := superseded IS NOT NULL;
    has_archived                       boolean := archived IS NOT NULL;
    has_has_warning                    boolean := has_warning IS NOT NULL;
    has_internal_number                boolean := internal_number IS NOT NULL;
    has_from_date                      boolean := from_date IS NOT NULL;
    has_until_date                     boolean := until_date IS NOT NULL;
    has_min_total                      boolean := min_total IS NOT NULL;
    has_max_total                      boolean := max_total IS NOT NULL;
    has_export_status                  boolean := export_status IS NOT NULL;
    has_paid_status                    boolean := paid_status IS NOT NULL;
    has_document_types                 boolean := ARRAY_LENGTH(document_types, 1) IS NOT NULL;
    has_document_category_ids          boolean := ARRAY_LENGTH(document_category_ids, 1) IS NOT NULL;
    has_partner_company_ids            boolean := partner_company_ids IS NOT NULL;
    has_client_company_tag_ids         boolean := client_company_tag_ids IS NOT NULL;
    has_client_company_cost_center_ids boolean := client_company_cost_center_ids IS NOT NULL;
    has_client_company_cost_unit_ids   boolean := client_company_cost_unit_ids IS NOT NULL;
    has_general_ledger_account_ids     boolean := general_ledger_account_ids IS NOT NULL;
    has_document_workflow_step_ids     boolean := document_workflow_step_ids IS NOT NULL;
    has_is_credit_memo                 boolean := is_credit_memo IS NOT NULL;
    has_has_pain001_payment            boolean := has_pain001_payment IS NOT NULL;
    has_has_pain008_direct_debit       boolean := has_pain008_direct_debit IS NOT NULL;
    has_is_payment_reminder_sent       boolean := is_payment_reminder_sent IS NOT NULL;
    has_is_approved                    boolean := is_approved IS NOT NULL;
    has_requested_approver_ids         boolean := ARRAY_LENGTH(requested_approver_ids, 1) IS NOT NULL;
    has_invoice_completeness_details   boolean := invoice_completeness_details IS NOT NULL;
    has_is_duplicate                   boolean := is_duplicate IS NOT NULL;
    has_has_comments                   boolean := has_comments IS NOT NULL;
    has_comment_mentioned_user_id      boolean := comment_mentioned_user_id IS NOT NULL;
    has_money_account_ids              boolean := ARRAY_LENGTH(money_account_ids, 1) IS NOT NULL;
    has_base_document_ids              boolean := ARRAY_LENGTH(base_document_ids, 1) IS NOT NULL;
    has_is_recurring                   boolean := is_recurring IS NOT NULL;
    has_contract_type                  boolean := contract_type IS NOT NULL;
    has_document_real_estate_object_instance_ids boolean := document_real_estate_object_instance_ids IS NOT NULL;
    -- order
    has_order_bys boolean := ARRAY_LENGTH(order_bys, 1) IS NOT NULL;
    order_by      public.filter_documents_order_by; -- used for the loop

    -- loops
    i_invoice_completeness_detail public.invoice_completeness_detail;

    stmt text;
BEGIN
    IF has_document_ids THEN
        -- provided document_ids are considered filter subsets. when set, filter within
        stmt := FORMAT(
            $stmt$
            SELECT d.* FROM (
                SELECT * FROM public.document
                WHERE %1$s (id = ANY(%2$L))

            ) AS d
            $stmt$,
            CASE exclude_document_ids WHEN true THEN 'NOT' END, -- %1$s
            document_ids -- %2$L
        );
    ELSIF has_search_text THEN
        -- filter_documents_of_client_company_and_fulltext(_only_ts) has a high cost which suggests the planner to filter for
        -- clients documents matching the fulltext, and then proceed with matching the rest of filters
        if (length(search_text) < 3) or (search_text ~ '^\d+$') then
            -- search_text is just numbers or is too short, _only_ts is faster here
            stmt := FORMAT(
                $stmt$
                select d.* from (
                    select * from public.document where document.client_company_id = %1$L
                    -- not locked by a review group
                    and not exists (select from public.review_group_document
                        inner join public.review_group on review_group.id = review_group_document.review_group_id
                    where review_group_document.source_document_id = document.id
                    and review_group.documents_lock_id is not null)
                    -- a "more" correct check is `public.document_is_visual`. however, we expect all visual documents to have pages
                    and document.num_pages > 0
                    and searchtext @@ plainto_tsquery('german', %2$L)
                ) AS d
                $stmt$,
                client_company_id, -- %1$L
                search_text -- %2$L
            );
        else
            stmt := FORMAT(
                $stmt$
                select d.* from (
                    select * from public.document where document.client_company_id = %1$L
                    -- not locked by a review group
                    and not exists (select from public.review_group_document
                        inner join public.review_group on review_group.id = review_group_document.review_group_id
                    where review_group_document.source_document_id = document.id
                    and review_group.documents_lock_id is not null)
                    -- a "more" correct check is `public.document_is_visual`. however, we expect all visual documents to have pages
                    and document.num_pages > 0
                    and (searchtext @@ plainto_tsquery('german', %2$L)
                        or (fulltext_w_invoice ilike '%%' || %2$L || '%%'))
                ) AS d
                $stmt$,
                client_company_id, -- %1$L
                search_text -- %2$L
            );
        end if;
    ELSE
        -- filter_documents_of_client_company has a high cost which suggests the planner to
        -- filter for clients documents, and then proceed with matching the rest of filters
        stmt := FORMAT(
            $stmt$
            select d.* from (
                select * from public.document where document.client_company_id = %1$L
                -- not locked by a review group
                and not exists (select from public.review_group_document
                    inner join public.review_group on review_group.id = review_group_document.review_group_id
                where review_group_document.source_document_id = document.id
                and review_group.documents_lock_id is not null)
                -- a "more" correct check is `public.document_is_visual`. however, we expect all visual documents to have pages
                and document.num_pages > 0
            ) AS d
            $stmt$,
            client_company_id -- %1$L
        );
    END IF;

    ---- JOINS ----

    -- invoice
    IF (
        has_search_text
    ) OR (
        has_internal_number
    ) OR (
        has_from_date
    ) OR (
        has_until_date
    ) OR (
        has_min_total
    ) OR (
        has_max_total
    ) OR (
        has_paid_status
    ) OR (
        has_partner_company_ids
    ) OR (
        has_invoice_completeness_details
    ) OR (
        has_is_credit_memo
    ) OR (
        has_is_duplicate
    ) OR (
        has_order_bys
    ) OR (
        -- TODO: drop when we completely drop abacus. Erik: 2025-04-28 we have dropped abacus!
        has_export_status
    ) OR (
        has_contract_type
    ) THEN

        stmt := stmt || FORMAT(
            $stmt$
                LEFT JOIN public.invoice AS i ON i.document_id = d.id
                LEFT JOIN public.other_document AS od ON od.document_id = d.id
                LEFT JOIN public.partner_company AS pc ON (pc.id = i.partner_company_id OR pc.id = od.partner_company_id)
            $stmt$
        );

    END IF;

    -- invoice accounting item
    IF order_bys && '{GENERAL_LEDGER_ACCOUNT_ASC,GENERAL_LEDGER_ACCOUNT_DESC}'
    THEN

        stmt := stmt || FORMAT(
            $stmt$
                LEFT JOIN LATERAL (
                    SELECT
                        invoice_accounting_item.*,
                        substring(general_ledger_account."number" from '(\d+)')::numeric as general_ledger_account_number
                    FROM public.invoice_accounting_item
                        INNER JOIN public.general_ledger_account
                        ON general_ledger_account.id = invoice_accounting_item.general_ledger_account_id
                    WHERE invoice_accounting_item.invoice_document_id = i.document_id
                    ORDER BY general_ledger_account_number ASC -- when multiple invoice acc. items are present, use the one with the lower GLA number
                    LIMIT 1
                ) AS iai ON true
            $stmt$
        );

    END IF;

    IF order_bys && '{REAL_ESTATE_OBJECT_ASC,REAL_ESTATE_OBJECT_DESC}'
    THEN

        stmt := stmt || FORMAT(
            $stmt$
                LEFT JOIN public.document_real_estate_object(d) AS dreo ON true
            $stmt$
        );

    END IF;

    -- document_category is always inner joined because we always filter some
    -- specific document types out. see last `WHERE` statement below
    stmt := stmt || FORMAT(
        $stmt$
            INNER JOIN public.document_category AS dc ON dc.id = d.category_id
        $stmt$
    );

    ---- WHERES ----

    stmt := stmt || ' WHERE ';

    -- search_text
    IF has_document_ids AND has_search_text THEN

        -- a subset of documents is selected, appending fulltext
        stmt := stmt || FORMAT(
            $stmt$(
                (d.searchtext @@ plainto_tsquery('german', %1$L))
                or (d.fulltext_w_invoice ilike '%%'||%1$L||'%%')
            )AND$stmt$,
            search_text -- %1$L
        );

    END IF;

    -- superseded
    IF has_superseded THEN

        stmt := stmt || FORMAT(
            $stmt$(
                %1$L = d.superseded
            )AND$stmt$,
            superseded -- %1$L
        );

    END IF;

    -- archived
    IF has_archived and archived = false THEN

        stmt := stmt || FORMAT(
            $stmt$(
                %1$L = d.archived
            )AND$stmt$,
            archived -- %1$L
        );

    END IF;

    -- has_warning
    IF has_has_warning THEN

        -- TODO: add warning filter

    END IF;

    -- internal_number
    IF has_internal_number THEN

        stmt := stmt || FORMAT(
            $stmt$(
                i.internal_number IS NOT NULL AND i.internal_number = %1$L
            )AND$stmt$,
            internal_number -- %1$L
        );

    END IF;

    -- from_date
    IF has_from_date THEN

        CASE date_filter_type
            WHEN 'DOCUMENT_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        COALESCE(i.invoice_date, od.document_date, d.import_date) >= %1$L
                    )AND$stmt$,
                    from_date -- %1$L
                );
            WHEN 'INVOICE_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        i.invoice_date IS NOT NULL AND i.invoice_date >= %1$L
                    )AND$stmt$,
                    from_date -- %1$L
                );
            WHEN 'DUE_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        public.invoice_payment_due_date(i) IS NOT NULL AND public.invoice_payment_due_date(i) >= %1$L
                    )AND$stmt$,
                    from_date -- %1$L
                );
            WHEN 'DISCOUNT_DUE_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        public.invoice_payment_discount_due_date(i) IS NOT NULL AND public.invoice_payment_discount_due_date(i) >= %1$L
                    )AND$stmt$,
                    from_date -- %1$L
                );
            WHEN 'IMPORT_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        d.import_date::date >= %1$L
                    )AND$stmt$,
                    from_date -- %1$L
                );
            WHEN 'PAID_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        public.invoice_payment_paid_date(i) IS NOT NULL AND public.invoice_payment_paid_date(i) >= %1$L
                    )AND$stmt$,
                    from_date -- %1$L
                );
            WHEN 'DELIVERED_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        (i.delivered_from IS NOT NULL AND i.delivered_from >= %1$L)
                        OR (i.delivered_until IS NOT NULL AND i.delivered_until >= %1$L)
                    )AND$stmt$,
                    from_date -- %1$L
                );
            ELSE
        END CASE;

    END IF;

    -- until_date
    IF has_until_date THEN

        CASE date_filter_type
            WHEN 'DOCUMENT_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        COALESCE(i.invoice_date, od.document_date, d.import_date) <= %1$L
                    )AND$stmt$,
                    until_date -- %1$L
                );
            WHEN 'INVOICE_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        i.invoice_date IS NOT NULL AND i.invoice_date <= %1$L
                    )AND$stmt$,
                    until_date -- %1$L
                );
            WHEN 'DUE_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        public.invoice_payment_due_date(i) IS NOT NULL AND public.invoice_payment_due_date(i) <= %1$L
                    )AND$stmt$,
                    until_date -- %1$L
                );
            WHEN 'DISCOUNT_DUE_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        public.invoice_payment_discount_due_date(i) IS NOT NULL AND public.invoice_payment_discount_due_date(i) <= %1$L
                    )AND$stmt$,
                    until_date -- %1$L
                );
            WHEN 'IMPORT_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        d.import_date::date <= %1$L
                    )AND$stmt$,
                    until_date -- %1$L
                );
            WHEN 'PAID_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        public.invoice_payment_paid_date(i) IS NOT NULL AND public.invoice_payment_paid_date(i) <= %1$L
                    )AND$stmt$,
                    until_date -- %1$L
                );
            WHEN 'DELIVERED_DATE' THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        (i.delivered_from IS NOT NULL AND i.delivered_from <= %1$L)
                        OR (i.delivered_until IS NOT NULL AND i.delivered_until <= %1$L)

                    )AND$stmt$,
                    until_date -- %1$L
                );
            ELSE
        END CASE;

    END IF;

    -- min_total
    IF has_min_total THEN

        stmt := stmt || FORMAT(
            $stmt$(
                i.total IS NOT NULL AND ABS(i.total) >= ABS(%1$L)
            )AND$stmt$,
            min_total -- %1$L
        );

    END IF;

    -- max_total
    IF has_max_total THEN

        stmt := stmt || FORMAT(
            $stmt$(
                i.total IS NOT NULL AND ABS(i.total) <= ABS(%1$L)
            )AND$stmt$,
            max_total -- %1$L
        );

    END IF;

    -- export_status
    IF has_export_status THEN

        CASE export_status
            WHEN 'NOT_EXPORTED' THEN
                stmt := stmt || $stmt$(
                    (
                        NOT EXISTS (SELECT 1 FROM public.document_export_document AS ded WHERE ded.document_id = d.id LIMIT 1)
                    ) AND (
                        NOT EXISTS (SELECT FROM public.export_document
                            WHERE export_document.document_id = d.id
                            -- TODO: cant work like this, we have to consider the LATEST export document entry
                            -- AND export_document.removed_at is null
                            )
                    )
                )AND$stmt$;
            WHEN 'NOT_EXPORTED_FOR_BOOKING' THEN
                stmt := stmt || $stmt$(
                    NOT EXISTS (
                        SELECT 1 FROM public.document_export_document AS ded
                            INNER JOIN public.document_export AS de ON (de.id = ded.document_export_id)
                        WHERE (
                            de.booking_export
                        ) AND (
                            ded.document_id = d.id
                        )
                        LIMIT 1
                    ) AND NOT EXISTS (
                        SELECT FROM public.export_document
                            INNER JOIN public.export ON export.id = export_document.export_id
                        WHERE export_document.document_id = d.id
                        -- even if removed_at, it was ONCE exported for booking and is therefore in the bookkeeping system
                        -- if you want to change this, PLEASE TALK TO Stefan Spiegel FIRST!
                        -- AND export_document.removed_at is null
                        AND export.booking_export
                    )
                )AND$stmt$;
            WHEN 'NOT_EXPORTED_FOR_READY_FOR_BOOKING' THEN
                stmt := stmt || $stmt$(
                    NOT EXISTS (
                        SELECT FROM public.export_document
                            INNER JOIN public.export ON export.id = export_document.export_id
                        WHERE export_document.document_id = d.id
                        -- TODO: cant work like this, we have to consider the LATEST export document entry
                        -- AND export_document.removed_at is null
                        AND export.ready_for_booking_export
                    )
                )AND$stmt$;
            WHEN 'EXPORTED' THEN
                stmt := stmt || $stmt$(
                    (
                        EXISTS (SELECT 1 FROM public.document_export_document AS ded WHERE ded.document_id = d.id LIMIT 1)
                    ) OR (
                        EXISTS (SELECT FROM public.export_document
                            WHERE export_document.document_id = d.id
                            -- TODO: cant work like this, we have to consider the LATEST export document entry
                            -- AND export_document.removed_at is null
                            )
                    )
                )AND$stmt$;
            WHEN 'EXPORTED_FOR_BOOKING' THEN
                stmt := stmt || $stmt$(
                    EXISTS (
                        SELECT 1 FROM public.document_export_document AS ded
                            INNER JOIN public.document_export AS de ON (de.id = ded.document_export_id)
                        WHERE (
                            de.booking_export
                        ) AND (
                            ded.document_id = d.id
                        )
                        LIMIT 1
                    ) OR EXISTS (
                        SELECT FROM public.export_document
                            INNER JOIN public.export ON export.id = export_document.export_id
                        WHERE export_document.document_id = d.id
                        -- even if removed_at, it was ONCE exported for booking and is therefore in the bookkeeping system
                        -- if you want to change this, PLEASE TALK TO Stefan Spiegel FIRST!
                        -- AND export_document.removed_at is null
                        AND export.booking_export
                    )
                )AND$stmt$;
            WHEN 'EXPORTED_FOR_READY_FOR_BOOKING' THEN
                stmt := stmt || $stmt$(
                    EXISTS (
                        SELECT FROM public.export_document
                            INNER JOIN public.export ON export.id = export_document.export_id
                        WHERE export_document.document_id = d.id
                        -- TODO: cant work like this, we have to consider the LATEST export document entry
                        -- AND export_document.removed_at is null
                        AND export.ready_for_booking_export
                    )
                )AND$stmt$;
            ELSE -- TODO: other export statuses
        END CASE;

    END IF;

    -- paid_status
    IF has_paid_status THEN

        CASE paid_status
            WHEN 'NOT_PAYABLE' THEN
                stmt := stmt || $stmt$(
                    (i IS NULL)
                    -- this is a credit-note with an invoice whose total is equal or smaller
                    or (i.credit_memo
                        and i.credit_memo_for_invoice_document_id is not null
                        and exists (select from public.invoice as i_in
                            where not i_in.credit_memo
                            and i_in.document_id = i.credit_memo_for_invoice_document_id
                            and i_in.total <= i.total))
                    -- this is an invoice with a credit-note whose total is equal or greater
                    or (not i.credit_memo
                        and exists (select from public.invoice as i_in
                            where i_in.credit_memo
                            and i_in.credit_memo_for_invoice_document_id is not null
                            and i_in.credit_memo_for_invoice_document_id = i.document_id
                            and i_in.total >= i.total))
                    or (i.payment_status = 'NOT_PAYABLE')
                )AND$stmt$;
            WHEN 'NOT_PAID' THEN
                stmt := stmt || $stmt$(
                    (
                        i.partially_paid
                    ) OR (
                        (
                            i.paid_date IS NULL
                        ) AND (
                            i.payment_status IS NULL
                        ) AND (
                            not exists (select from public.partner_company
                                where partner_company.id = i.partner_company_id
                                and partner_company.paid_with_direct_debit)
                        ) AND (
                            NOT EXISTS (SELECT 1 FROM public.bank_payment AS bp WHERE (bp.document_id = d.id AND bp.status = 'FINISHED') LIMIT 1)
                        ) AND (
                            -- much faster then using the `document_money_transaction` view
                            NOT EXISTS (
                                (
                                    SELECT 1 FROM public.document_bank_transaction AS dbt WHERE (dbt.document_id = d.id) LIMIT 1
                                ) UNION (
                                    SELECT 1 FROM public.document_credit_card_transaction AS dcct WHERE (dcct.document_id = d.id) LIMIT 1
                                ) UNION (
                                    SELECT 1 FROM public.document_cash_transaction AS dct WHERE (dct.document_id = d.id) LIMIT 1
                                ) UNION (
                                    SELECT 1 FROM public.document_paypal_transaction AS dpt WHERE (dpt.document_id = d.id) LIMIT 1
                                ) UNION (
                                    SELECT 1 FROM public.document_stripe_transaction AS dst WHERE (dst.document_id = d.id) LIMIT 1
                                )
                            )
                        ) AND (
                            dc.booking_type IS NULL
                            OR dc.ignore_booking_type_paid_assumption
                        ) AND (
                            (
                                -- this is an invoice without a credit-note whose total is equal or greater
                                not i.credit_memo
                                and not exists (select from public.invoice as i_in
                                    where i_in.credit_memo
                                    and i_in.credit_memo_for_invoice_document_id is not null
                                    and i_in.credit_memo_for_invoice_document_id = i.document_id
                                    and i_in.total >= i.total)
                            ) OR (
                                -- this is a credit-note without an invoice whose total is equal or smaller
                                i.credit_memo
                                and not exists (select from public.invoice as i_in
                                    where not i_in.credit_memo
                                    and i_in.document_id = i.credit_memo_for_invoice_document_id
                                    and i_in.total <= i.total)
                            )
                        )
                    )
                )AND$stmt$;
            WHEN 'PARTIALLY_PAID' THEN
                stmt := stmt || $stmt$(
                    i.partially_paid
                )AND$stmt$;
            WHEN 'PAID' THEN
                stmt := stmt || $stmt$(
                    not i.partially_paid
                ) AND (
                    (
                        i.paid_date IS NOT NULL
                    ) OR (
                        i.payment_status IS NOT NULL
                    ) OR (
                        exists (select from public.partner_company
                            where partner_company.id = i.partner_company_id
                            and partner_company.paid_with_direct_debit)
                    ) OR (
                        EXISTS (SELECT 1 FROM public.bank_payment AS bp WHERE (bp.document_id = d.id AND bp.status = 'FINISHED') LIMIT 1)
                    ) OR (
                        EXISTS (
                            (
                                SELECT 1 FROM public.document_bank_transaction AS dbt WHERE (dbt.document_id = d.id) LIMIT 1
                            ) UNION (
                                SELECT 1 FROM public.document_credit_card_transaction AS dcct WHERE (dcct.document_id = d.id) LIMIT 1
                            ) UNION (
                                SELECT 1 FROM public.document_cash_transaction AS dct WHERE (dct.document_id = d.id) LIMIT 1
                            ) UNION (
                                SELECT 1 FROM public.document_paypal_transaction AS dpt WHERE (dpt.document_id = d.id) LIMIT 1
                            ) UNION (
                                SELECT 1 FROM public.document_stripe_transaction AS dst WHERE (dst.document_id = d.id) LIMIT 1
                            )
                        )
                    ) OR (
                        dc.booking_type IS NOT NULL
                    )
                )AND$stmt$;
            WHEN 'PAID_WITH_MONEY_ACCOUNT' THEN
                stmt := stmt || $stmt$(
                    not i.partially_paid
                ) AND (
                    (
                        EXISTS (SELECT 1 FROM public.bank_payment AS bp WHERE (bp.document_id = d.id AND bp.status = 'FINISHED') LIMIT 1)
                    ) OR (
                        EXISTS (
                            (
                                SELECT 1 FROM public.document_bank_transaction AS dbt WHERE (dbt.document_id = d.id) LIMIT 1
                            ) UNION (
                                SELECT 1 FROM public.document_credit_card_transaction AS dcct WHERE (dcct.document_id = d.id) LIMIT 1
                            ) UNION (
                                SELECT 1 FROM public.document_cash_transaction AS dct WHERE (dct.document_id = d.id) LIMIT 1
                            ) UNION (
                                SELECT 1 FROM public.document_paypal_transaction AS dpt WHERE (dpt.document_id = d.id) LIMIT 1
                            ) UNION (
                                SELECT 1 FROM public.document_stripe_transaction AS dst WHERE (dst.document_id = d.id) LIMIT 1
                            )
                        )
                    ) OR (
                        dc.booking_type IS NOT NULL
                    )
                )AND$stmt$;
            WHEN 'PAID_WITH_BANK' THEN
                stmt := stmt || $stmt$(
                    not i.partially_paid
                ) AND (
                    (
                        i.payment_status = 'BANK'
                    ) OR (
                        EXISTS (
                            SELECT 1 FROM public.document_bank_transaction AS dbt WHERE (dbt.document_id = d.id) LIMIT 1
                        )
                    )
                )AND$stmt$;
            WHEN 'PAID_WITH_CREDITCARD' THEN
                stmt := stmt || $stmt$(
                    not i.partially_paid
                ) AND (
                    (
                        i.payment_status = 'CREDITCARD'
                    ) OR (
                        EXISTS (
                            SELECT 1 FROM public.document_credit_card_transaction AS dcct WHERE (dcct.document_id = d.id) LIMIT 1
                        )
                    )
                )AND$stmt$;
            WHEN 'PAID_WITH_CASH' THEN
                stmt := stmt || $stmt$(
                    not i.partially_paid
                ) AND (
                    (
                        i.payment_status = 'CASH'
                    ) OR (
                        EXISTS (
                            SELECT 1 FROM public.document_cash_transaction AS dct WHERE (dct.document_id = d.id) LIMIT 1
                        )
                    ) OR (
                        dc.booking_type = 'CASH_BOOK'
                    )
                )AND$stmt$;
            WHEN 'PAID_WITH_PAYPAL' THEN
                stmt := stmt || $stmt$(
                    not i.partially_paid
                ) AND (
                    (
                        i.payment_status = 'PAYPAL'
                    ) OR (
                        EXISTS (
                            SELECT 1 FROM public.document_paypal_transaction AS dpt WHERE (dpt.document_id = d.id) LIMIT 1
                        )
                    )
                )AND$stmt$;
            WHEN 'EXPENSES_PAID' THEN
                stmt := stmt || $stmt$(
                    not i.partially_paid
                ) AND (
                    i.payment_status = 'EXPENSES_PAID'
                )AND$stmt$;
            WHEN 'PAID_WITH_TRANSFERWISE' THEN
                stmt := stmt || $stmt$(
                    not i.partially_paid
                ) AND (
                    i.payment_status = 'TRANSFERWISE'
                )AND$stmt$;
            WHEN 'PAID_WITH_DIRECT_DEBIT' THEN
                stmt := stmt || $stmt$(
                    not i.partially_paid
                ) AND (
                    i.payment_status = 'DIRECT_DEBIT'
                    or exists (select from public.partner_company
                        where partner_company.id = i.partner_company_id
                        and partner_company.paid_with_direct_debit)
                )AND$stmt$;
            ELSE
        END CASE;

    END IF;

    -- document_types
    IF has_document_types THEN

        stmt := stmt || FORMAT(
            $stmt$(
                %1$s (dc.document_type = ANY(%2$L))
            )AND$stmt$,
            CASE exclude_document_types WHEN true THEN 'NOT' END, -- %1$s
            document_types -- %2$L
        );

    END IF;

    -- document_category_ids
    IF has_document_category_ids THEN

        stmt := stmt || FORMAT(
            $stmt$(
                %1$s (d.category_id = ANY(%2$L))
            )AND$stmt$,
            CASE exclude_document_category_ids WHEN true THEN 'NOT' END, -- %1$s
            document_category_ids -- %2$L
        );

    END IF;

    -- partner_company_ids
    IF has_partner_company_ids THEN
        IF ARRAY_LENGTH(partner_company_ids, 1) IS NOT NULL THEN

            stmt := stmt || FORMAT(
                $stmt$(
                    (
                        NOT (pc IS NULL)
                    ) AND (
                        %1$s (pc.id = ANY(%2$L))
                    )
                )AND$stmt$,
                CASE exclude_partner_company_ids WHEN true THEN 'NOT' END, -- %1$s
                partner_company_ids -- %2$L
            );

        ELSE

            stmt := stmt || FORMAT(
                $stmt$(
                    %1$s (pc IS NULL)
                )AND$stmt$,
                CASE exclude_partner_company_ids WHEN false THEN 'NOT' END -- %1$s
                -- {} and not exclude => docs with any of the specified type
                -- {} and exclude     => docs without any of the specified type
            );

        END IF;
    END IF;

    -- client_company_tag_ids
    IF has_client_company_tag_ids THEN
        IF ARRAY_LENGTH(client_company_tag_ids, 1) IS NOT NULL THEN

            stmt := stmt || FORMAT(
                $stmt$(
                    %1$s (
                        EXISTS (
                            SELECT 1 FROM public.document_tag AS dt
                            WHERE dt.document_id = d.id AND dt.client_company_tag_id = ANY(%2$L)
                            LIMIT 1
                        )
                        OR
                        EXISTS (
                            select from public.real_estate_object_client_company_tag
                            inner join public.document_real_estate_object
                            on document_real_estate_object.object_instance_id = real_estate_object_client_company_tag.object_instance_id
                            where document_real_estate_object.document_id = d.id
                            and real_estate_object_client_company_tag.client_company_tag_id = any(%2$L)
                        )
                    )
                )AND$stmt$,
                CASE exclude_client_company_tag_ids WHEN true THEN 'NOT' END, -- %1$s
                client_company_tag_ids -- %2$L
            );

        ELSE

            stmt := stmt || FORMAT(
                $stmt$(
                    %1$s (
                        EXISTS (
                            SELECT 1 FROM public.document_tag AS dt
                            WHERE dt.document_id = d.id
                            LIMIT 1
                        )
                        OR
                        EXISTS (
                            select from public.real_estate_object_client_company_tag
                            inner join public.document_real_estate_object
                            on document_real_estate_object.object_instance_id = real_estate_object_client_company_tag.object_instance_id
                            where document_real_estate_object.document_id = d.id
                        )
                    )
                )AND$stmt$,
                CASE exclude_client_company_tag_ids WHEN true THEN 'NOT' END -- %1$s
                -- {} and not exclude => docs with any of the specified type
                -- {} and exclude     => docs without any of the specified type
            );

        END IF;
    END IF;

    -- client_company_cost_center_ids
    IF has_client_company_cost_center_ids THEN
        IF ARRAY_LENGTH(client_company_cost_center_ids, 1) IS NOT NULL THEN

            IF exclude_client_company_cost_center_ids THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        (
                            -- invoice cost-center
                            NOT EXISTS (
                                SELECT 1 FROM public.invoice_cost_center AS icc
                                WHERE icc.document_id = d.id AND icc.client_company_cost_center_id = ANY(%1$L)
                                LIMIT 1
                            )
                        ) AND (
                            -- invoice accounting item cost-center
                            NOT EXISTS (
                                SELECT FROM public.invoice_accounting_item_cost_center
                                    INNER JOIN public.invoice_accounting_item ON invoice_accounting_item.id = invoice_accounting_item_cost_center.invoice_accounting_item_id
                                WHERE invoice_accounting_item.invoice_document_id = d.id
                                AND invoice_accounting_item_cost_center.client_company_cost_center_id = ANY(%1$L)
                            )
                        )
                    )AND$stmt$,
                    client_company_cost_center_ids -- %1$L
                );
            ELSE
                stmt := stmt || FORMAT(
                    $stmt$(
                        (
                            -- invoice cost-center
                            EXISTS (
                                SELECT 1 FROM public.invoice_cost_center AS icc
                                WHERE icc.document_id = d.id AND icc.client_company_cost_center_id = ANY(%1$L)
                                LIMIT 1
                            )
                        ) OR (
                            -- invoice accounting item cost-center
                            EXISTS (
                                SELECT FROM public.invoice_accounting_item_cost_center
                                    INNER JOIN public.invoice_accounting_item ON invoice_accounting_item.id = invoice_accounting_item_cost_center.invoice_accounting_item_id
                                WHERE invoice_accounting_item.invoice_document_id = d.id
                                AND invoice_accounting_item_cost_center.client_company_cost_center_id = ANY(%1$L)
                            )
                        )
                    )AND$stmt$,
                    client_company_cost_center_ids -- %1$L
                );
            END IF;

        ELSE

            IF exclude_client_company_cost_center_ids THEN
                stmt := stmt || $stmt$(
                    (
                        -- invoice cost-center
                        NOT EXISTS (
                            SELECT 1 FROM public.invoice_cost_center AS icc
                            WHERE icc.document_id = d.id
                            LIMIT 1
                        )
                    ) AND (
                        -- invoice accounting item cost-center
                        NOT EXISTS (
                            SELECT FROM public.invoice_accounting_item_cost_center
                                INNER JOIN public.invoice_accounting_item ON invoice_accounting_item.id = invoice_accounting_item_cost_center.invoice_accounting_item_id
                            WHERE invoice_accounting_item.invoice_document_id = d.id
                        )
                    )
                )AND$stmt$;
            ELSE
                stmt := stmt || $stmt$(
                    (
                        -- invoice cost-center
                        EXISTS (
                            SELECT 1 FROM public.invoice_cost_center AS icc
                            WHERE icc.document_id = d.id
                            LIMIT 1
                        )
                    ) OR (
                        -- invoice accounting item cost-center
                        EXISTS (
                            SELECT FROM public.invoice_accounting_item_cost_center
                                INNER JOIN public.invoice_accounting_item ON invoice_accounting_item.id = invoice_accounting_item_cost_center.invoice_accounting_item_id
                            WHERE invoice_accounting_item.invoice_document_id = d.id
                        )
                    )
                )AND$stmt$;
            END IF;

        END IF;
    END IF;

    -- client_company_cost_unit_ids
    IF has_client_company_cost_unit_ids THEN
        IF ARRAY_LENGTH(client_company_cost_unit_ids, 1) IS NOT NULL THEN

            IF exclude_client_company_cost_unit_ids THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        (
                            -- invoice cost-center
                            NOT EXISTS (
                                SELECT 1 FROM public.invoice_cost_unit AS icc
                                WHERE icc.invoice_document_id = d.id AND icc.client_company_cost_unit_id = ANY(%1$L)
                                LIMIT 1
                            )
                        ) AND (
                            -- invoice accounting item cost-center
                            NOT EXISTS (
                                SELECT FROM public.invoice_accounting_item_cost_unit
                                    INNER JOIN public.invoice_accounting_item ON invoice_accounting_item.id = invoice_accounting_item_cost_unit.invoice_accounting_item_id
                                WHERE invoice_accounting_item.invoice_document_id = d.id
                                AND invoice_accounting_item_cost_unit.client_company_cost_unit_id = ANY(%1$L)
                            )
                        )
                    )AND$stmt$,
                    client_company_cost_unit_ids -- %1$L
                );
            ELSE
                stmt := stmt || FORMAT(
                    $stmt$(
                        (
                            -- invoice cost-center
                            EXISTS (
                                SELECT 1 FROM public.invoice_cost_unit AS icc
                                WHERE icc.invoice_document_id = d.id AND icc.client_company_cost_unit_id = ANY(%1$L)
                                LIMIT 1
                            )
                        ) OR (
                            -- invoice accounting item cost-center
                            EXISTS (
                                SELECT FROM public.invoice_accounting_item_cost_unit
                                    INNER JOIN public.invoice_accounting_item ON invoice_accounting_item.id = invoice_accounting_item_cost_unit.invoice_accounting_item_id
                                WHERE invoice_accounting_item.invoice_document_id = d.id
                                AND invoice_accounting_item_cost_unit.client_company_cost_unit_id = ANY(%1$L)
                            )
                        )
                    )AND$stmt$,
                    client_company_cost_unit_ids -- %1$L
                );
            END IF;

        ELSE

            IF exclude_client_company_cost_unit_ids THEN
                stmt := stmt || $stmt$(
                    (
                        -- invoice cost-center
                        NOT EXISTS (
                            SELECT 1 FROM public.invoice_cost_unit AS icc
                            WHERE icc.invoice_document_id = d.id
                            LIMIT 1
                        )
                    ) AND (
                        -- invoice accounting item cost-center
                        NOT EXISTS (
                            SELECT FROM public.invoice_accounting_item_cost_unit
                                INNER JOIN public.invoice_accounting_item ON invoice_accounting_item.id = invoice_accounting_item_cost_unit.invoice_accounting_item_id
                            WHERE invoice_accounting_item.invoice_document_id = d.id
                        )
                    )
                )AND$stmt$;
            ELSE
                stmt := stmt || $stmt$(
                    (
                        -- invoice cost-center
                        EXISTS (
                            SELECT 1 FROM public.invoice_cost_unit AS icc
                            WHERE icc.invoice_document_id = d.id
                            LIMIT 1
                        )
                    ) OR (
                        -- invoice accounting item cost-center
                        EXISTS (
                            SELECT FROM public.invoice_accounting_item_cost_unit
                                INNER JOIN public.invoice_accounting_item ON invoice_accounting_item.id = invoice_accounting_item_cost_unit.invoice_accounting_item_id
                            WHERE invoice_accounting_item.invoice_document_id = d.id
                        )
                    )
                )AND$stmt$;
            END IF;

        END IF;
    END IF;

    -- general_ledger_account_ids
    IF has_general_ledger_account_ids THEN
        IF ARRAY_LENGTH(general_ledger_account_ids, 1) IS NOT NULL THEN

            IF exclude_general_ledger_account_ids THEN
                stmt := stmt || FORMAT(
                    $stmt$(
                        (
                            -- invoice accounting item general ledger account
                            NOT EXISTS (
                                SELECT FROM public.invoice_accounting_item
                                WHERE invoice_accounting_item.invoice_document_id = d.id
                                AND invoice_accounting_item.general_ledger_account_id = ANY(%1$L)
                            )
                        )
                    )AND$stmt$,
                    general_ledger_account_ids -- %1$L
                );
            ELSE
                stmt := stmt || FORMAT(
                    $stmt$(
                        (
                            -- invoice accounting item general ledger account
                            EXISTS (
                                SELECT FROM public.invoice_accounting_item
                                WHERE invoice_accounting_item.invoice_document_id = d.id
                                AND invoice_accounting_item.general_ledger_account_id = ANY(%1$L)
                            )
                        )
                    )AND$stmt$,
                    general_ledger_account_ids -- %1$L
                );
            END IF;

        ELSE

            IF exclude_general_ledger_account_ids THEN
                stmt := stmt || $stmt$(
                    (
                        -- invoice accounting item general ledger account
                        NOT EXISTS (
                            SELECT FROM public.invoice_accounting_item
                            WHERE invoice_accounting_item.invoice_document_id = d.id
                        )
                    )
                )AND$stmt$;
            ELSE
                stmt := stmt || $stmt$(
                    (
                        -- invoice accounting item general ledger account
                        EXISTS (
                            SELECT FROM public.invoice_accounting_item
                            WHERE invoice_accounting_item.invoice_document_id = d.id
                        )
                    )
                )AND$stmt$;
            END IF;

        END IF;
    END IF;

    -- document_workflow_step_ids
    IF has_document_workflow_step_ids THEN
        IF ARRAY_LENGTH(document_workflow_step_ids, 1) IS NOT NULL THEN

            stmt := stmt || FORMAT(
                $stmt$(
                    %1$s (d.workflow_step_id = ANY(%2$L))
                )AND$stmt$,
                CASE exclude_document_workflow_step_ids WHEN true THEN 'd.workflow_step_id IS NULL OR NOT' END, -- %1$s
                document_workflow_step_ids -- %2$L
            );

        ELSE

            stmt := stmt || FORMAT(
                $stmt$(
                    d.workflow_step_id IS %1$s NULL
                )AND$stmt$,
                CASE exclude_document_workflow_step_ids WHEN false THEN 'NOT' END -- %1$s
                -- {} and not exclude => docs with any of the specified type
                -- {} and exclude     => docs without any of the specified type
            );

        END IF;
    END IF;

    -- is_credit_memo
    IF has_is_credit_memo THEN

        stmt := stmt || FORMAT(
            $stmt$(
                i.credit_memo = %1$L
            )AND$stmt$,
            is_credit_memo -- %1$L
        );

    END IF;

    -- has_pain001_payment
    IF has_has_pain001_payment THEN

        stmt := stmt || FORMAT(
            $stmt$(
                EXISTS (
                    SELECT 1 FROM public.pain001_payment WHERE invoice_document_id = d.id LIMIT 1
                ) = %1$L
            )AND$stmt$,
            has_pain001_payment -- %1$L
        );

    END IF;

    -- has_pain008_direct_debit
    IF has_has_pain008_direct_debit THEN

        stmt := stmt || FORMAT(
            $stmt$(
                EXISTS (
                    SELECT 1 FROM public.pain008_payment WHERE invoice_document_id = d.id LIMIT 1
                ) = %1$L
            )AND$stmt$,
            has_pain008_direct_debit -- %1$L
        );

    END IF;

    -- is_payment_reminder_sent
    IF has_is_payment_reminder_sent THEN

        stmt := stmt || FORMAT(
            $stmt$(
                EXISTS (
                    SELECT 1 FROM public.document_payment_reminder WHERE document_id = d.id LIMIT 1
                ) = %1$L
            )AND$stmt$,
            is_payment_reminder_sent -- %1$L
        );

    END IF;

    -- is_approved (if there are requested approver IDs then the next conditional will ensure that the specific approvals are closed)
    IF has_is_approved AND NOT has_requested_approver_ids THEN

        case when public.is_client_company_feature_active(client_company_id, 'APPROVED_WITHOUT_VERIFIERS')
            and not public.user_has_verifying_access_for_client_company(private.current_user(), client_company_id)
        then stmt := stmt || FORMAT(
            $stmt$(
                -- filtering by released documents gives us always releasable ones
                coalesce((public.is_document_approved_without_verifiers(d.id) = %1$L), false)
            )AND$stmt$,
            is_approved -- %1$L
        );
        else stmt := stmt || FORMAT(
            $stmt$(
                -- filtering by released documents gives us always releasable ones
                coalesce((public.is_document_approved(d.id) = %1$L), false)
            )AND$stmt$,
            is_approved -- %1$L
        );
        end case;

    END IF;

    -- requested_approver_ids
    IF has_requested_approver_ids THEN

        stmt := stmt || FORMAT(
            $stmt$(
                exists (select from public.document_approval_request
                    where document_approval_request.document_id = d.id
                    -- is_approved = null -> we dont care
                    -- is_approved = true -> approval request must be closed
                    -- is_approved = false -> approval request must be open
                    and (%1$L is null
                        or (%1$L = exists (select from public.document_approval where document_approval.request_id = document_approval_request.id)))
                    -- requested_approver_ids = {} -> *this statement will not be NOT be used, check conditional above*
                    -- requested_approver_ids = {some-user-id} -> approval request aimed to this specific user
                    and (
                        -- blank approver type matches the client company user
                        exists (
                            select from control.client_company_user
                            where client_company_id = %3$L
                            and user_id = any(%2$L)
                            and (
                                -- anyone except verifier can approve
                                (document_approval_request.blank_approver_type = 'ANYONE'
                                    and role_name <> 'VERIFIER')
                                -- blank approval type must match the role
                                or document_approval_request.blank_approver_type::varchar = role_name
                            )
                            -- group approvals cannot be approved by the requester, even if he belongs to the group
                            and document_approval_request.requester_id <> client_company_user.user_id
                        )
                        -- user group approval request (we use array position to allow for `null`values to be checked)
                        or document_approval_request.user_group_id in (
                            select user_group_user.user_group_id from public.user_group_user
                            where array_position(%2$L, user_group_user.user_id) is not null
                        )
                        -- direct approval request (we use array position to allow for `null` values to be checked)
                        or array_position(%2$L, document_approval_request.approver_id) is not null))
            )AND$stmt$,
            is_approved, -- %1$L
            requested_approver_ids, -- %2$L
            client_company_id -- %3$L
        );

    END IF;

    -- invoice_completeness_details
    IF has_invoice_completeness_details THEN

        stmt := stmt || E'(\n\t\t\t\t\t';
        foreach i_invoice_completeness_detail in
            array coalesce(nullif(invoice_completeness_details, '{}'),
                enum_range(null::public.invoice_completeness_detail)) -- coalesce to all enum values
        loop
            if exclude_invoice_completeness_details then
                case i_invoice_completeness_detail
                    when 'REAL_ESTATE_OBJECT' then
                        stmt := stmt || $stmt$(
                            not exists (select from public.document_real_estate_object where document_real_estate_object.document_id = i.document_id)
                        )OR$stmt$;
                    when 'ACCOUNTING_ITEMS' then
                        stmt := stmt || $stmt$(
                            not exists (select from public.invoice_accounting_item where invoice_accounting_item.invoice_document_id = i.document_id)
                            -- TODO: still necessary? this check exists in ACCOUNTING_ITEMS_NO_REMAINING_AMOUNT
                            -- or not public.invoice_accounting_items_remaining_amount_is_zero(i)
                        )OR$stmt$;
                    when 'ACCOUNTING_ITEMS_NO_REMAINING_AMOUNT' then
                        stmt := stmt || $stmt$(
                            not public.invoice_accounting_items_remaining_amount_is_zero(i)
                        )OR$stmt$;
                    when 'ACCOUNTING_ITEMS_COST_CENTERS' then
                        stmt := stmt || $stmt$(
                            not coalesce((select every(not (invoice_accounting_item_cost_center is null)) from public.invoice_accounting_item
                                left join public.invoice_accounting_item_cost_center on invoice_accounting_item_cost_center.invoice_accounting_item_id = invoice_accounting_item.id
                            where invoice_accounting_item.invoice_document_id = i.document_id), false)
                        )OR$stmt$;
                    when 'ACCOUNTING_ITEMS_COST_UNITS' then
                        stmt := stmt || $stmt$(
                            not coalesce((select every(not (invoice_accounting_item_cost_unit is null)) from public.invoice_accounting_item
                                left join public.invoice_accounting_item_cost_unit on invoice_accounting_item_cost_unit.invoice_accounting_item_id = invoice_accounting_item.id
                            where invoice_accounting_item.invoice_document_id = i.document_id), false)
                        )OR$stmt$;
                    when 'PARTNER_ACCOUNT' then
                        stmt := stmt || $stmt$(
                            public.invoice_account_number(i) is null
                        )OR$stmt$;
                    when 'IBAN' then
                        stmt := stmt || $stmt$(
                            public.invoice_payment_iban(i) is null
                        )OR$stmt$;
                    when 'BIC' then
                        stmt := stmt || $stmt$(
                            public.invoice_payment_bic(i) is null
                        )OR$stmt$;
                    when 'DUE_DATE' then
                        stmt := stmt || $stmt$(
                            public.invoice_payment_due_date(i) is null
                        )OR$stmt$;
                    when 'DISCOUNT_UNTIL' then
                        stmt := stmt || $stmt$(
                            public.invoice_payment_discount_due_date(i) is null
                        )OR$stmt$;
                    else
                        stmt := stmt || FORMAT(
                            $stmt$(
                                i.%1$I is null
                            )OR$stmt$,
                            lower(i_invoice_completeness_detail::text) -- %1$I
                        );
                end case;
            else
                case i_invoice_completeness_detail
                    when 'REAL_ESTATE_OBJECT' then
                        stmt := stmt || $stmt$(
                            exists (select from public.document_real_estate_object where document_real_estate_object.document_id = i.document_id)
                        )AND$stmt$;
                    when 'ACCOUNTING_ITEMS' then
                        stmt := stmt || $stmt$(
                            exists (select from public.invoice_accounting_item where invoice_accounting_item.invoice_document_id = i.document_id)
                            -- TODO: still necessary? this check exists in ACCOUNTING_ITEMS_NO_REMAINING_AMOUNT
                            -- and public.invoice_accounting_items_remaining_amount_is_zero(i)
                        )AND$stmt$;
                    when 'ACCOUNTING_ITEMS_NO_REMAINING_AMOUNT' then
                        stmt := stmt || $stmt$(
                            public.invoice_accounting_items_remaining_amount_is_zero(i)
                        )AND$stmt$;
                    when 'ACCOUNTING_ITEMS_COST_CENTERS' then
                        stmt := stmt || $stmt$(
                            select
                                every(not (invoice_accounting_item_cost_center is null))
                                and public.invoice_accounting_items_remaining_amount_is_zero(i)
                            from public.invoice_accounting_item
                                left join public.invoice_accounting_item_cost_center on invoice_accounting_item_cost_center.invoice_accounting_item_id = invoice_accounting_item.id
                            where invoice_accounting_item.invoice_document_id = i.document_id
                        )AND$stmt$;
                    when 'ACCOUNTING_ITEMS_COST_UNITS' then
                        stmt := stmt || $stmt$(
                            select
                                every(not (invoice_accounting_item_cost_unit is null))
                                and public.invoice_accounting_items_remaining_amount_is_zero(i)
                            from public.invoice_accounting_item
                                left join public.invoice_accounting_item_cost_unit on invoice_accounting_item_cost_unit.invoice_accounting_item_id = invoice_accounting_item.id
                            where invoice_accounting_item.invoice_document_id = i.document_id
                        )AND$stmt$;
                    when 'PARTNER_ACCOUNT' then
                        stmt := stmt || $stmt$(
                            public.invoice_account_number(i) is not null
                        )AND$stmt$;
                    when 'IBAN' then
                        stmt := stmt || $stmt$(
                            public.invoice_payment_iban(i) is not null
                        )AND$stmt$;
                    when 'BIC' then
                        stmt := stmt || $stmt$(
                            public.invoice_payment_bic(i) is not null
                        )AND$stmt$;
                    when 'DUE_DATE' then
                        stmt := stmt || $stmt$(
                            public.invoice_payment_due_date(i) is not null
                        )AND$stmt$;
                    when 'DISCOUNT_UNTIL' then
                        stmt := stmt || $stmt$(
                            public.invoice_payment_discount_due_date(i) is not null
                        )AND$stmt$;
                    else
                        stmt := stmt || FORMAT(
                            $stmt$(
                                i.%1$I is not null
                            )AND$stmt$,
                            lower(i_invoice_completeness_detail::text) -- %1$I
                        );
                end case;
            end if;
        end loop;
        if exclude_invoice_completeness_details then
            -- remove last "or" from loop
            stmt := trim(trailing ')OR' from stmt);
        else
            -- remove last "and" from loop
            stmt := trim(trailing ')AND' from stmt);
        end if;

        stmt := stmt || E')\n\t\t)AND';

    END IF;

    -- is_duplicate
    IF has_is_duplicate THEN

        stmt := stmt || FORMAT(
            $stmt$(
                public.invoice_has_duplicate_invoices(i) = %1$L
            )AND$stmt$,
            is_duplicate -- %1$L
        );

    END IF;

    -- has_comments
    IF has_has_comments THEN

        stmt := stmt || FORMAT(
            $stmt$(
                %1$s EXISTS(
                    SELECT FROM public.document_comment
                    WHERE document_comment.document_id = d.id
                )
            )AND$stmt$,
            CASE has_comments WHEN false THEN 'NOT' END -- %1$s
        );

    END IF;

    -- comment_mentioned_user_is
    IF has_comment_mentioned_user_id THEN

        stmt := stmt || FORMAT(
            $stmt$(
                exists(
                    select from public.document_comment
                    where document_comment.document_id = d.id
                    and %1$L = any(public.document_comment_mentioned_user_ids(document_comment))
                    -- comment_mentioned_user_id_is_seen = null -> we dont care
                    -- comment_mentioned_user_id_is_seen = true -> comment was seen
                    -- comment_mentioned_user_id_is_seen = false -> comment is not seen
                    and (%2$L is null
                        or %2$L = exists(
                            select from public.document_comment_seen
                            where document_comment_seen.document_comment_id = document_comment.id
                            and document_comment_seen.seen_by = %1$L

                            union all

                            -- own comments don't have seen states, they're considered seen already
                            select from generate_series(1, 1)
                            where document_comment.commented_by = %1$L))
                )
            )AND$stmt$,
            comment_mentioned_user_id, -- %1$L
            comment_mentioned_user_id_is_seen -- %2$L
        );

    END IF;

    -- money_account_ids
    IF has_money_account_ids THEN

        stmt := stmt || FORMAT(
            $stmt$(
                EXISTS (
                    (
                        SELECT 1 FROM public.document_bank_transaction
                            INNER JOIN public.bank_transaction
                            ON bank_transaction.id = document_bank_transaction.bank_transaction_id
                        WHERE document_bank_transaction.document_id = d.id
                        AND bank_transaction.account_id = ANY(%1$L)
                        LIMIT 1
                    ) UNION (
                        SELECT 1 FROM public.document_credit_card_transaction
                            INNER JOIN public.credit_card_transaction
                            ON credit_card_transaction.id = document_credit_card_transaction.credit_card_transaction_id
                        WHERE document_credit_card_transaction.document_id = d.id
                        AND credit_card_transaction.account_id = ANY(%1$L)
                        LIMIT 1
                    ) UNION (
                        SELECT 1 FROM public.document_cash_transaction
                            INNER JOIN public.cash_transaction
                            ON cash_transaction.id = document_cash_transaction.cash_transaction_id
                        WHERE document_cash_transaction.document_id = d.id
                        AND cash_transaction.account_id = ANY(%1$L)
                        LIMIT 1
                    ) UNION (
                        SELECT 1 FROM public.document_paypal_transaction
                            INNER JOIN public.paypal_transaction
                            ON paypal_transaction.id = document_paypal_transaction.paypal_transaction_id
                        WHERE document_paypal_transaction.document_id = d.id
                        AND paypal_transaction.account_id = ANY(%1$L)
                        LIMIT 1
                    ) UNION (
                        SELECT 1 FROM public.document_stripe_transaction
                            INNER JOIN public.stripe_transaction
                            ON stripe_transaction.id = document_stripe_transaction.stripe_transaction_id
                        WHERE document_stripe_transaction.document_id = d.id
                        AND stripe_transaction.account_id = ANY(%1$L)
                        LIMIT 1
                    )
                )
            )AND$stmt$,
            money_account_ids -- %1$L
        );

    END IF;

    -- base_document_ids
    if has_base_document_ids then

        stmt := stmt || FORMAT(
            $stmt$(
                d.id = any(%1$L)
                or d.base_document_id = any(%1$L)
            )AND$stmt$,
            base_document_ids -- %1$L
        );

    end if;

    -- is_recurring
    if has_is_recurring then

        stmt := stmt || FORMAT(
            $stmt$(
                exists (
                    select from public.document_recurrence
                    where (document_recurrence.document_id = d.id
                        or document_recurrence.document_id = d.base_document_id)
                    and (document_recurrence.disabled_at is null
                        or exists (select from public.document_recurrence_document
                            where document_recurrence_document.recurrence_id = document_recurrence.id))
                ) = %1$L
            )AND$stmt$,
            is_recurring -- %1$L
        );

    end if;

    -- contract_type
    if has_contract_type then

        stmt := stmt || FORMAT(
            $stmt$(
                od.contract_type = %1$L
            )AND$stmt$,
            contract_type -- %1$L
        );

    end if;

    -- document_real_estate_object
    IF has_document_real_estate_object_instance_ids THEN
        IF ARRAY_LENGTH(document_real_estate_object_instance_ids, 1) IS NOT NULL THEN

            stmt := stmt || FORMAT(
                $stmt$(
                    %1$s EXISTS (
                        SELECT FROM public.document_real_estate_object
                        WHERE document_real_estate_object.document_id = d.id
                        AND document_real_estate_object.object_instance_id = ANY(%2$L)
                    )
                )AND$stmt$,
                CASE exclude_document_real_estate_object_instance_ids WHEN true THEN 'NOT' END, -- %1$s
                document_real_estate_object_instance_ids -- %2$L
            );

        ELSE

            stmt := stmt || FORMAT(
                $stmt$(
                    %1$s exists (
                        SELECT FROM public.document_real_estate_object
                        WHERE document_real_estate_object.document_id = d.id
                    )
                )AND$stmt$,
                CASE exclude_document_real_estate_object_instance_ids WHEN true THEN 'NOT' END -- %1$s
                -- {} and not exclude => docs with any of the specified type
                -- {} and exclude     => docs without any of the specified type
            );

        END IF;
    END IF;

    -- TODO: remove since public.filter_documents_of_client_company contains the always present availability filters.
    -- currently easier to just append `AND(true)` than to conditionally remove the last AND (so that the order by works).
    stmt := stmt || $stmt$(true)$stmt$;

    ---- end WHERES ----

    ---- ORDER BYS ----

    stmt := stmt || ' ORDER BY '; -- prepare order by

    IF has_order_bys THEN

        FOREACH order_by IN ARRAY order_bys LOOP

            CASE order_by
                WHEN 'DOCUMENT_DATE_ASC' THEN
                    stmt := stmt || 'COALESCE(i.invoice_date, od.document_date, d.import_date) ASC,';
                WHEN 'DOCUMENT_DATE_DESC' THEN
                    stmt := stmt || 'COALESCE(i.invoice_date, od.document_date, d.import_date) DESC,';
                WHEN 'IMPORT_DATE_ASC' THEN
                    stmt := stmt || 'd.import_date ASC,';
                WHEN 'IMPORT_DATE_DESC' THEN
                    stmt := stmt || 'd.import_date DESC,';
                WHEN 'INVOICE_DATE_ASC' THEN
                    stmt := stmt || 'i.invoice_date ASC NULLS FIRST,';
                WHEN 'INVOICE_DATE_DESC' THEN
                    stmt := stmt || 'i.invoice_date DESC NULLS LAST,';
                -- due date sort is useful in asc order, therefore put nulls to last
                WHEN 'DUE_DATE_ASC' THEN
                    stmt := stmt || 'public.invoice_payment_due_date(i) ASC NULLS LAST,';
                WHEN 'DUE_DATE_DESC' THEN
                    stmt := stmt || 'public.invoice_payment_due_date(i) DESC NULLS FIRST,';
                WHEN 'DISCOUNT_DUE_DATE_ASC' THEN
                    stmt := stmt || 'public.invoice_payment_discount_due_date(i) ASC NULLS FIRST,';
                WHEN 'DISCOUNT_DUE_DATE_DESC' THEN
                    stmt := stmt || 'public.invoice_payment_discount_due_date(i) DESC NULLS LAST,';
                WHEN 'PAID_DATE_ASC' THEN
                    stmt := stmt || 'public.invoice_payment_paid_date(i) ASC NULLS FIRST,';
                WHEN 'PAID_DATE_DESC' THEN
                    stmt := stmt || 'public.invoice_payment_paid_date(i) DESC NULLS LAST,';
                WHEN 'TOTAL_ASC' THEN
                    stmt := stmt || 'i.total ASC NULLS FIRST,';
                WHEN 'TOTAL_DESC' THEN
                    stmt := stmt || 'i.total DESC NULLS LAST,';
                WHEN 'PARTNER_COMPANY_ASC' THEN
                    stmt := stmt || 'pc.derived_name ASC NULLS FIRST,';
                    -- additionally sort by due dates and then dates within partners sort (always asc, requires attention on the top)
                    stmt := stmt || 'public.invoice_payment_due_date(i) ASC NULLS LAST,';
                    stmt := stmt || 'COALESCE(i.invoice_date, od.document_date, d.import_date) ASC,';
                WHEN 'PARTNER_COMPANY_DESC' THEN
                    stmt := stmt || 'pc.derived_name DESC NULLS LAST,';
                    -- additionally sort by due dates and then dates within partners sort (always asc, requires attention on the top)
                    stmt := stmt || 'public.invoice_payment_due_date(i) ASC NULLS LAST,';
                    stmt := stmt || 'COALESCE(i.invoice_date, od.document_date, d.import_date) ASC,';
                WHEN 'INVOICE_NUMBER_ASC' THEN
                    stmt := stmt || 'i.invoice_number ASC NULLS FIRST,';
                WHEN 'INVOICE_NUMBER_DESC' THEN
                    stmt := stmt || 'i.invoice_number DESC NULLS LAST,';
                WHEN 'GENERAL_LEDGER_ACCOUNT_ASC' THEN
                    stmt := stmt || 'iai.general_ledger_account_number ASC NULLS FIRST,';
                    stmt := stmt || 'COALESCE(i.invoice_date, od.document_date, d.import_date) ASC,';
                WHEN 'GENERAL_LEDGER_ACCOUNT_DESC' THEN
                    stmt := stmt || 'iai.general_ledger_account_number DESC NULLS LAST,';
                    stmt := stmt || 'COALESCE(i.invoice_date, od.document_date, d.import_date) ASC,';
                WHEN 'REAL_ESTATE_OBJECT_ASC' THEN
                    stmt := stmt || 'dreo.number ASC NULLS FIRST,';
                    stmt := stmt || 'COALESCE(i.invoice_date, od.document_date, d.import_date) ASC,';
                WHEN 'REAL_ESTATE_OBJECT_DESC' THEN
                    stmt := stmt || 'dreo.number DESC NULLS LAST,';
                    stmt := stmt || 'COALESCE(i.invoice_date, od.document_date, d.import_date) ASC,';
                ELSE
            END CASE;

        END LOOP;

        stmt := RTRIM(stmt, ','); -- remove last `comma (,)`
    ELSE

        -- default order
        stmt := stmt || 'd.import_date DESC';

    END IF;

    ---- end ORDER BYS ----

    RETURN stmt;
END
$$
LANGUAGE plpgsql IMMUTABLE;
