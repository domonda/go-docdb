CREATE TYPE public.partner_company_open_items_stats AS (
    partner_company_name              text,
    not_due_liabilities               float8,
    not_due_assets                    float8,
    due_within_21_liabilities         float8,
    due_within_21_assets              float8,
    due_within_14_liabilities         float8,
    due_within_14_assets              float8,
    due_within_7_liabilities          float8,
    due_within_7_assets               float8,
    due_within_2_liabilities          float8,
    due_within_2_assets               float8,
    overdue_less_30_liabilities       float8,
    overdue_less_30_assets            float8,
    overdue_between_30_60_liabilities float8,
    overdue_between_30_60_assets      float8,
    overdue_more_60_liabilities       float8,
    overdue_more_60_assets            float8,
    overdue_liabilities               float8,
    overdue_assets                    float8,
    total_liabilities                 float8,
    total_assets                      float8
);

COMMENT ON COLUMN public.partner_company_open_items_stats.partner_company_name IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.not_due_liabilities IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.not_due_assets IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.due_within_21_liabilities IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.due_within_21_assets IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.due_within_14_liabilities IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.due_within_14_assets IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.due_within_7_liabilities IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.due_within_7_assets IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.due_within_2_liabilities IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.due_within_2_assets IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.overdue_less_30_liabilities IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.overdue_less_30_assets IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.overdue_between_30_60_liabilities IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.overdue_between_30_60_assets IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.overdue_more_60_liabilities IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.overdue_more_60_assets IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.overdue_liabilities IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.overdue_assets IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.total_liabilities IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats.total_assets IS '@notNull';

----

CREATE TYPE public.partner_company_open_items_stats_filter AS (
    client_company_id   uuid,
    partner_company_ids uuid[]
);

COMMENT ON COLUMN public.partner_company_open_items_stats_filter.client_company_id IS '@notNull';
COMMENT ON COLUMN public.partner_company_open_items_stats_filter.partner_company_ids IS '@notNull';

----

CREATE FUNCTION public.derive_partner_companies_open_items_stats(
    filter public.partner_company_open_items_stats_filter
) RETURNS SETOF public.partner_company_open_items_stats AS $$
    WITH open_items AS (
        SELECT i.*, dc.document_type FROM public.invoice AS i
            INNER JOIN (
                public.document AS d
                INNER JOIN public.document_category AS dc ON (dc.id = d.category_id)
            ) ON (d.id = i.document_id)
        WHERE (
            -- documents from client company
            d.client_company_id = derive_partner_companies_open_items_stats.filter.client_company_id
        ) AND (
            -- not locked by a review group
            not exists (select from public.review_group_document
                inner join public.review_group on review_group.id = review_group_document.review_group_id
            where review_group_document.source_document_id = d.id
            and review_group.documents_lock_id is not null)
        ) AND (
            -- not superseded
            NOT d.superseded
        ) AND (
            -- not superseded
            NOT EXISTS(SELECT 1 FROM public.document AS superseded_d WHERE (superseded_d.supersedes = d.id) LIMIT 1)
        ) AND (
            -- not paid
            (
                i.paid_date IS NULL
            ) AND (
                i.payment_status IS NULL
            ) AND (
                NOT EXISTS (SELECT 1 FROM public.bank_payment AS bp WHERE (bp.document_id = d.id AND bp.status = 'FINISHED') LIMIT 1)
            ) AND (
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
            )
        ) AND (
            -- must be either an incoming or outgoing invoice
            (
                dc.document_type = 'OUTGOING_INVOICE'
            ) OR (
                dc.document_type = 'INCOMING_INVOICE'
            )
        ) AND (
            -- must not have a booking type
            dc.booking_type IS NULL
            OR dc.ignore_booking_type_paid_assumption
        )
        -- does it really need to have a linked partner company?
        -- AND (
        --     -- must have a partner company linked
        --     i.partner_company_id IS NOT NULL
        -- )
    ), not_due AS (
        SELECT * FROM open_items WHERE (
            -- must have a due date
            due_date IS NOT NULL
        ) AND (
            -- today < due_date
            current_date < due_date
            ---- (today + 21) < due_date
            -- (current_date + interval '21' day) < due_date
        )
    ), due_within_21 AS (
        SELECT * FROM open_items WHERE (
            -- must have a due date
            due_date IS NOT NULL
        ) AND (
            -- today <= due_date <= (today + 21 days)
            (current_date <= due_date) AND (due_date <= (current_date + interval '21' day))
        )
    ), due_within_14 AS (
        SELECT * FROM open_items WHERE (
            -- must have a due date
            due_date IS NOT NULL
        ) AND (
            -- today <= due_date <= (today + 14 days)
            (current_date <= due_date) AND (due_date <= (current_date + interval '14' day))
        )
    ), due_within_7 AS (
        SELECT * FROM open_items WHERE (
            -- must have a due date
            due_date IS NOT NULL
        ) AND (
            -- today <= due_date <= (today + 7 days)
            (current_date <= due_date) AND (due_date <= (current_date + interval '7' day))
        )
    ), due_within_2 AS (
        SELECT * FROM open_items WHERE (
            -- must have a due date
            due_date IS NOT NULL
        ) AND (
            -- today <= due_date <= (today + 2 days)
            (current_date <= due_date) AND (due_date <= (current_date + interval '2' day))
        )
    ), overdue_less_30 AS (
        SELECT * FROM open_items WHERE (
            -- must have a due date
            due_date IS NOT NULL
        ) AND (
            -- today > due_date >= (today - 30 days)
            (current_date > due_date) AND (due_date >= (current_date - interval '30' day))
        )
    ), overdue_between_30_60 AS (
        SELECT * FROM open_items WHERE (
            -- must have a due date
            due_date IS NOT NULL
        ) AND (
            -- (today - 30 days) >= due_date >= (today - 60 days)
            ((current_date - interval '30' day) >= due_date) AND (due_date >= (current_date - interval '60' day))
        )
    ), overdue_more_60 AS (
        SELECT * FROM open_items WHERE (
            -- must have a due date
            due_date IS NOT NULL
        ) AND (
            -- (today - 60 days) > due_date
            (current_date - interval '60' day) > due_date
        )
    ), overdue AS (
        SELECT * FROM open_items WHERE (
            -- must have a due date
            due_date IS NOT NULL
        ) AND (
            -- today > due_date
            current_date > due_date
        )
    )
    (
        SELECT
            partner_company.derived_name, -- partner_company_name
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM not_due
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- not_due_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM not_due
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- not_due_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_21
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- due_within_21_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_21
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- due_within_21_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_14
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- due_within_14_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_14
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- due_within_14_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_7
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- due_within_7_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_7
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- due_within_7_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_2
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- due_within_2_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_2
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- due_within_2_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_less_30
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- overdue_less_30_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_less_30
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- overdue_less_30_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_between_30_60
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- overdue_between_30_60_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_between_30_60
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- overdue_between_30_60_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_more_60
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- overdue_more_60_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_more_60
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- overdue_more_60_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- overdue_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue
                WHERE (
                    partner_company_id = id
                )
            ), 0), -- overdue_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM open_items
                WHERE (
                    partner_company_id = id
                )
            ), 0) AS total_liabilities, -- total_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM open_items
                WHERE (
                    partner_company_id = id
                )
            ), 0) AS total_assets -- total_assets
        FROM public.partner_company
        WHERE (id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
        ORDER BY
            total_liabilities DESC,
            total_assets DESC
    ) UNION ALL (
        SELECT
            '(REST)', -- partner_company_name
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM not_due
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- not_due_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM not_due
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- not_due_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_21
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- due_within_21_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_21
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- due_within_21_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_14
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- due_within_14_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_14
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- due_within_14_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_7
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- due_within_7_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_7
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- due_within_7_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_2
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- due_within_2_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM due_within_2
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- due_within_2_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_less_30
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- overdue_less_30_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_less_30
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- overdue_less_30_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_between_30_60
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- overdue_between_30_60_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_between_30_60
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- overdue_between_30_60_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_more_60
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- overdue_more_60_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue_more_60
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- overdue_more_60_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- overdue_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM overdue
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- overdue_assets
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'INCOMING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'OUTGOING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM open_items
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0), -- total_liabilities
            COALESCE((
                SELECT
                    SUM(
                        CASE
                            WHEN (
                                (
                                    (document_type = 'OUTGOING_INVOICE') AND (NOT credit_memo)
                                ) OR (
                                    (document_type = 'INCOMING_INVOICE') AND (credit_memo)
                                )
                            ) THEN COALESCE(ABS(total) / COALESCE(conversion_rate, 1), 0.0)
                            ELSE 0.0
                        END
                    )
                FROM open_items
                WHERE (
                    NOT (partner_company_id = ANY(derive_partner_companies_open_items_stats.filter.partner_company_ids))
                )
            ), 0) -- total_assets
    )
$$
LANGUAGE SQL STABLE STRICT;
