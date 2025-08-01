CREATE TYPE public.open_items_type AS ENUM (
  'ASSETS',     -- outgoing invoices
  'LIABILITIES' -- incoming invoices
);

CREATE TYPE public.filter_open_items_order_by AS ENUM (
  'IMPORT_DATE_ASC',
  'IMPORT_DATE_DESC',
  'INVOICE_DATE_ASC',
  'INVOICE_DATE_DESC',
  'DUE_DATE_ASC',
  'DUE_DATE_DESC',
  'PARTNER_COMPANY_ASC',
  'PARTNER_COMPANY_DESC',
  'TOTAL_ASC',
  'TOTAL_DESC',
  'INVOICE_NUMBER_ASC',
  'INVOICE_NUMBER_DESC'
);

CREATE FUNCTION private.filter_open_items(
    -- core
    client_company_id uuid, -- $1
    search_text       text, -- $2
    open_items_type   public.open_items_type, -- $3
    order_by          public.filter_open_items_order_by, -- order_by is dynamic
    -- category
    document_category_ids uuid[], -- $4
    -- partner
    partner_company_ids uuid[], -- $5
    -- amount
    min_total float8, -- $6
    max_total float8, -- $7
    -- date
    date_filter_type public.filter_documents_date_filter_type, -- $8
    from_date        date, -- $9
    until_date       date, -- $10
    -- tags
    tag_ids uuid[], -- $11
    -- cost centers
    cost_center_ids uuid[], -- $12
    -- workflows
    workflow_ids      uuid[], -- $13
    workflow_step_ids uuid[], -- $14
    -- pain001
    has_pain001_payment boolean -- $15
) RETURNS SETOF public.document AS
$$
BEGIN
    -- NOTE: the performance cost here of: planning on-the-fly VS having a cached plan, is negligible
    RETURN QUERY EXECUTE format(
        $query$
            SELECT d.* FROM (
                -- NOTE: the fulltext search is intentionally inside a sub-query
                -- because of optimization reasons (ask Denis for further explanation)
                (
                    -- fulltext on document
                    SELECT * FROM public.document WHERE (COALESCE(NULLIF(TRIM($2), ''), 'gutschrift') <> 'gutschrift') AND (
                        to_tsvector(
                            'german',
                            id || ' ' ||
                            fulltext || ' ' ||
                            COALESCE(title, '') || ' ' ||
                            public.filename_from_path(source_file)
                        ) @@ plainto_tsquery('german', $2)
                    )
                ) UNION (
                    -- fulltext on invoice
                    SELECT d.* FROM public.invoice AS i
                        INNER JOIN public.document AS d ON (i.document_id = d.id)
                    WHERE (COALESCE(NULLIF(TRIM($2), ''), 'gutschrift') <> 'gutschrift') AND (
                        to_tsvector(
                            'german',
                            COALESCE(i.partner_name, '') || ' ' ||
                            COALESCE(i.invoice_number, '') || ' ' ||
                            COALESCE(i.vat_id, '') || ' ' ||
                            i.currency || ' ' ||
                            format_money_int(i.net) || ' ' ||
                            format_money_int(i.total) || ' ' ||
                            format_money_german(i.net) || ' ' ||
                            format_money_german(i.total) || ' ' ||
                            COALESCE(i.iban, '') || ' ' ||
                            COALESCE(i.bic, '')
                        )
                        @@ plainto_tsquery('german', $2)
                    )
                ) UNION (
                    -- anti-join if the search_text is empty
                    SELECT * FROM public.document WHERE (COALESCE(NULLIF(TRIM($2), ''), 'gutschrift') = 'gutschrift')
                )
            ) AS d
                INNER JOIN public.document_category AS dc ON (dc.id = d.category_id)
                INNER JOIN (
                    public.invoice AS i
                    LEFT JOIN public.company AS c ON (i.partner_company_id = c.id)
                    LEFT JOIN LATERAL (
                        SELECT 1 FROM public.invoice_cost_center AS icc_in WHERE (
                            ($12 IS NOT NULL) AND (array_length($12, 1) > 0)
                        ) AND (
                            icc_in.document_id = i.document_id
                        ) AND (
                            icc_in.client_company_cost_center_id = ANY($12)
                        )
                        LIMIT 1
                    ) AS icc ON true
                ) ON (i.document_id = d.id)
                LEFT JOIN LATERAL (
                    SELECT 1 FROM public.document_tag AS dt_in WHERE (
                        ($11 IS NOT NULL) AND (array_length($11, 1) > 0)
                    ) AND (
                        dt_in.document_id = d.id
                    ) AND (
                        dt_in.client_company_tag_id = ANY($11)
                    )
                    LIMIT 1
                ) AS dt ON true
            WHERE (
                -- documents from client company
                d.client_company_id = $1
            ) AND (
                -- not locked by a review group
                where not exists (select from public.review_group_document
                    inner join public.review_group on review_group.id = review_group_document.review_group_id
                where review_group_document.source_document_id = d.id
                and review_group.documents_lock_id is not null)
            ) AND (
                -- not superseded
                NOT d.superseded
            ) AND (
                NOT EXISTS(SELECT 1 FROM public.document AS superseded_d WHERE (superseded_d.supersedes = d.id) LIMIT 1)
            ) AND (
                -- has a document version
                EXISTS (SELECT FROM docdb.document_version AS dv WHERE dv.document_id = d.id)
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
            ) AND (
                ($3 IS NULL) OR (
                    (
                        ($3 = 'ASSETS') AND (
                            (
                                (dc.document_type = 'OUTGOING_INVOICE') AND (NOT i.credit_memo)
                            ) OR (
                                (dc.document_type = 'INCOMING_INVOICE') AND (i.credit_memo)
                            )
                        )
                    ) OR (
                        ($3 = 'LIABILITIES') AND (
                            (
                                (dc.document_type = 'INCOMING_INVOICE') AND (NOT i.credit_memo)
                            ) OR (
                                (dc.document_type = 'OUTGOING_INVOICE') AND (i.credit_memo)
                            )
                        )
                    )
                )
            ) AND (
                ($4 IS NULL) OR (array_length($4, 1) = 0) OR (
                    d.category_id = ANY($4)
                )
            ) AND (
                ($11 IS NULL) OR (array_length($11, 1) = 0) OR (
                    NOT (dt IS NULL)
                )
            ) AND (
                ($14 IS NULL) OR (array_length($14, 1) = 0) OR (
                    d.workflow_step_id = ANY($14)
                )
            ) AND (
                ($13 IS NULL) OR (array_length($13, 1) = 0) OR (
                    EXISTS (
                        SELECT 1 FROM public.document_workflow_step AS dws WHERE (dws.id = d.workflow_step_id AND dws.workflow_id = ANY($13))
                    )
                )
            ) AND (
                ($6 IS NULL) OR (
                    COALESCE(ABS(i.total), 0) >= $6
                )
            ) AND (
                ($7 IS NULL) OR (
                    COALESCE(ABS(i.total), 0) <= $7
                )
            ) AND (
                ($9 IS NULL) OR (
                    (
                        ($8 = 'DUE_DATE') AND (i.due_date IS NOT NULL) AND (i.due_date >= $9)
                    ) OR (
                        ($8 = 'INVOICE_DATE') AND (i.invoice_date IS NOT NULL) AND (i.invoice_date >= $9)
                    ) OR (
                        (($8 IS NULL) OR ($8 = 'IMPORT_DATE')) AND (
                            (d.import_date::date >= $9)
                        )
                    )
                )
            ) AND (
                ($10 IS NULL) OR (
                    (
                        ($8 = 'DUE_DATE') AND (COALESCE(i.due_date, i.invoice_date, d.import_date::date) <= $10)
                    ) OR (
                        ($8 = 'INVOICE_DATE') AND (COALESCE(i.invoice_date, d.import_date::date) <= $10)
                    ) OR (
                        (($8 IS NULL) OR ($8 = 'IMPORT_DATE')) AND (
                            (d.import_date::date <= $10)
                        )
                    )
                )
            ) AND (
                ($5 IS NULL) OR (array_length($5, 1) = 0) OR (
                    (i.partner_company_id = ANY($5))
                )
            ) AND (
                ($12 IS NULL) OR (array_length($12, 1) = 0) OR (
                    NOT (icc IS NULL)
                )
            ) AND (
                ($15 IS NULL) OR (
                    $15 = (EXISTS (SELECT 1 FROM public.pain001_payment WHERE invoice_document_id = i.document_id))
                )
            ) AND (
                -- this is a hack until we have a proper filter element
                (COALESCE(TRIM($2), '') <> 'gutschrift') OR (
                    i.credit_memo
                )
            )
            ORDER BY
                %1$s
                COALESCE(i.invoice_number, d.source_id, '') DESC
        $query$,
        (
            CASE filter_open_items.order_by
                WHEN 'IMPORT_DATE_ASC' THEN 'd.import_date ASC,'
                WHEN 'IMPORT_DATE_DESC' THEN 'd.import_date DESC,'
                WHEN 'INVOICE_DATE_ASC' THEN 'i.invoice_date ASC NULLS FIRST,'
                WHEN 'INVOICE_DATE_DESC' THEN 'i.invoice_date DESC NULLS LAST,'
                WHEN 'DUE_DATE_ASC' THEN 'i.due_date ASC NULLS FIRST,'
                WHEN 'DUE_DATE_DESC' THEN 'i.due_date DESC NULLS LAST,'
                WHEN 'PARTNER_COMPANY_ASC' THEN 'COALESCE(c.name, i.partner_name) ASC NULLS FIRST,'
                WHEN 'PARTNER_COMPANY_DESC' THEN 'COALESCE(c.name, i.partner_name) DESC NULLS LAST,'
                WHEN 'TOTAL_ASC' THEN 'i.total ASC NULLS FIRST,'
                WHEN 'TOTAL_DESC' THEN 'i.total DESC NULLS LAST,'
                WHEN 'INVOICE_NUMBER_ASC' THEN 'i.invoice_number ASC NULLS FIRST,'
                WHEN 'INVOICE_NUMBER_DESC' THEN 'i.invoice_number DESC NULLS LAST,'
                ELSE NULL
            END
        ) -- %1$s
    ) USING
        filter_open_items.client_company_id, -- $1
        filter_open_items.search_text, -- $2
        filter_open_items.open_items_type, -- $3
        filter_open_items.document_category_ids, -- $4
        filter_open_items.partner_company_ids, -- $5
        filter_open_items.min_total, -- $6
        filter_open_items.max_total, -- $7
        filter_open_items.date_filter_type, -- $8
        filter_open_items.from_date, -- $9
        filter_open_items.until_date, -- $10
        filter_open_items.tag_ids, -- $11
        filter_open_items.cost_center_ids, -- $12
        filter_open_items.workflow_ids, -- $13
        filter_open_items.workflow_step_ids, -- $14
        filter_open_items.has_pain001_payment; -- $15
END;
$$
LANGUAGE plpgsql STABLE SECURITY DEFINER;

CREATE FUNCTION public.filter_open_items(
    -- core
    client_company_id uuid,
    search_text       text,
    open_items_type   public.open_items_type,
    order_by          public.filter_open_items_order_by,
    -- category
    document_category_ids uuid[],
    -- partner
    partner_company_ids uuid[],
    -- amount
    min_total float8,
    max_total float8,
    -- date
    date_filter_type public.filter_documents_date_filter_type,
    from_date        date,
    until_date       date,
    -- tags
    tag_ids uuid[],
    -- cost centers
    cost_center_ids uuid[],
    -- workflows
    workflow_ids      uuid[],
    workflow_step_ids uuid[],
    -- pain001
    has_pain001_payment boolean
) RETURNS SETOF public.document AS
$$
    SELECT foi.* FROM private.filter_open_items(
        filter_open_items.client_company_id,
        filter_open_items.search_text,
        filter_open_items.open_items_type,
        filter_open_items.order_by,
        filter_open_items.document_category_ids,
        filter_open_items.partner_company_ids,
        filter_open_items.min_total,
        filter_open_items.max_total,
        filter_open_items.date_filter_type,
        filter_open_items.from_date,
        filter_open_items.until_date,
        filter_open_items.tag_ids,
        filter_open_items.cost_center_ids,
        filter_open_items.workflow_ids,
        filter_open_items.workflow_step_ids,
        filter_open_items.has_pain001_payment
    ) AS foi
        INNER JOIN public.document AS d ON (d.id = foi.id)
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION public.filter_open_items IS 'Filters `Documents` which are currently matched as open items.';

----

CREATE TYPE public.open_items_statistics AS (
  net_sum             float8,
  total_sum           float8,
  liabilities_sum     float8,
  assets_sum          float8,
  same_document_types boolean
);
COMMENT ON COLUMN public.open_items_statistics.net_sum IS '@notNull';
COMMENT ON COLUMN public.open_items_statistics.total_sum IS '@notNull';
COMMENT ON COLUMN public.open_items_statistics.liabilities_sum IS '@notNull';
COMMENT ON COLUMN public.open_items_statistics.assets_sum IS '@notNull';
COMMENT ON COLUMN public.open_items_statistics.same_document_types IS '@notNull';
COMMENT ON TYPE public.open_items_statistics IS 'Statistics about the open items mirroring the `filterOpenItems` function.';

CREATE FUNCTION public.filter_open_items_statistics(
    -- core
    client_company_id uuid,
    search_text       text,
    open_items_type   public.open_items_type,
    order_by          public.filter_open_items_order_by,
    -- category
    document_category_ids uuid[],
    -- partner
    partner_company_ids uuid[],
    -- amount
    min_total float8,
    max_total float8,
    -- date
    date_filter_type public.filter_documents_date_filter_type,
    from_date        date,
    until_date       date,
    -- tags
    tag_ids uuid[],
    -- cost centers
    cost_center_ids uuid[],
    -- workflows
    workflow_ids      uuid[],
    workflow_step_ids uuid[],
    -- pain001
    has_pain001_payment boolean
) RETURNS public.open_items_statistics AS
$$
    SELECT
        COALESCE(SUM(COALESCE(ABS(i.net), 0.0) / COALESCE(i.conversion_rate, 1)), 0), -- net sum
        COALESCE(SUM(COALESCE(ABS(i.total), 0.0) / COALESCE(i.conversion_rate, 1)), 0), -- total sum
        COALESCE(
            SUM(
                CASE
                    WHEN (
                        (
                            (dc.document_type = 'INCOMING_INVOICE') AND (NOT i.credit_memo)
                        ) OR (
                            (dc.document_type = 'OUTGOING_INVOICE') AND (i.credit_memo)
                        )
                    ) THEN COALESCE(ABS(i.total) / COALESCE(i.conversion_rate, 1), 0.0)
                    ELSE 0.0
                END
            ),
            0
        ), -- liabilities
        COALESCE(
            SUM(
                CASE
                    WHEN (
                        (
                            (dc.document_type = 'OUTGOING_INVOICE') AND (NOT i.credit_memo)
                        ) OR (
                            (dc.document_type = 'INCOMING_INVOICE') AND (i.credit_memo)
                        )
                    ) THEN COALESCE(ABS(i.total) / COALESCE(i.conversion_rate, 1), 0.0)
                    ELSE 0.0
                END
            ),
            0
        ), -- assets
        COALESCE((COUNT(DISTINCT dc.document_type) = 1), false) -- same document_types across result
    FROM private.filter_open_items(
        filter_open_items_statistics.client_company_id,
        filter_open_items_statistics.search_text,
        filter_open_items_statistics.open_items_type,
        filter_open_items_statistics.order_by,
        filter_open_items_statistics.document_category_ids,
        filter_open_items_statistics.partner_company_ids,
        filter_open_items_statistics.min_total,
        filter_open_items_statistics.max_total,
        filter_open_items_statistics.date_filter_type,
        filter_open_items_statistics.from_date,
        filter_open_items_statistics.until_date,
        filter_open_items_statistics.tag_ids,
        filter_open_items_statistics.cost_center_ids,
        filter_open_items_statistics.workflow_ids,
        filter_open_items_statistics.workflow_step_ids,
        filter_open_items_statistics.has_pain001_payment
    ) AS foi
        INNER JOIN (
            public.document AS d
            INNER JOIN public.document_category AS dc ON (dc.id = d.category_id)
            INNER JOIN public.invoice AS i ON (i.document_id = d.id)
        ) ON (d.id = foi.id)
$$
LANGUAGE SQL STABLE;

COMMENT ON FUNCTION public.filter_open_items_statistics IS 'Statistics about the results of `filterOpenItems`.';
