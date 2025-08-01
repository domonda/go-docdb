CREATE VIEW private.op_health_check WITH (security_barrier) AS
    SELECT
        tb0.client_company_id,
        tb0.company_name,
        tb0.accounting_company_name,
        coalesce(tb1.status, 'INACTIVE')                   AS status,
        tb0.uploaded_documents_total,
        coalesce(tb2.uploaded_documents_current_month, 0)  AS uploaded_documents_current_month,
        tb0.last_document_upload_date,
        coalesce(tb3.number_of_active_users, 0)            AS number_of_active_users,
        NULL                                               AS restructure_group_open_since, -- was tb4
        coalesce(tb5.number_of_active_bank_connections, 0) AS number_of_active_bank_connections,
        tb5.last_bank_update_date,
        tb6.last_payment_date,
        coalesce(tb8.bludelta_sync_active, false)          AS bludelta_sync_active,
        CASE WHEN status = 'ACTIVE' AND tb1.valid_from > now()
            THEN tb1.valid_from
            ELSE NULL
            END                                            AS test_count_down
    FROM (
        SELECT
            cco.company_id                     AS client_company_id,
            coalesce(com.brand_name, com.name) AS company_name,
            acc.name                           AS accounting_company_name,
            count(doc.*)                       AS uploaded_documents_total,
            max(doc.created_at)                AS last_document_upload_date
        FROM public.company AS com
        INNER JOIN public.client_company AS cco ON com.id = cco.company_id
        INNER JOIN (
            public.accounting_company AS ac
            INNER JOIN public.company AS acc ON acc.id = ac.client_company_id
        ) ON ac.client_company_id = cco.accounting_company_client_company_id
        LEFT JOIN public.document AS doc ON cco.company_id = doc.client_company_id AND doc.num_pages > 0
        GROUP BY cco.company_id, com.brand_name, com.name, acc.name
    ) AS tb0
    LEFT JOIN (
        SELECT DISTINCT ON (client_company_id)
            client_company_id,
            status,
            valid_from
        FROM private.client_company_status
        ORDER BY client_company_id, valid_from DESC
    ) AS tb1 ON tb0.client_company_id = tb1.client_company_id
    LEFT JOIN (
        SELECT
            client_company_id,
            count(1) AS uploaded_documents_current_month
        FROM public.document
        WHERE document.created_at >= date_trunc('month', current_date)
        GROUP BY document.client_company_id
    ) AS tb2 ON tb0.client_company_id = tb2.client_company_id
    LEFT JOIN (
        SELECT
            usr.client_company_id AS client_company_id,
            count(usr.*)          AS number_of_active_users
        FROM public.user AS usr
        WHERE usr."type" = 'STANDARD'
        AND usr.enabled
        GROUP BY usr.client_company_id
    ) AS tb3 ON tb0.client_company_id = tb3.client_company_id
    LEFT JOIN (
        SELECT
            ba.client_company_id AS client_company_id,
            count(ba.*)          AS number_of_active_bank_connections,
            max(ba.updated_at)   AS last_bank_update_date
        FROM public.bank_account AS ba
        WHERE ba.xs2a_account_id IS NOT NULL
        GROUP BY ba.client_company_id
    ) AS tb5 ON tb0.client_company_id = tb5.client_company_id
    LEFT JOIN (
        SELECT DISTINCT ON (ba.client_company_id) client_company_id, last_payment_date
        FROM bank_account AS ba
        LEFT JOIN (
            SELECT
                bp.bank_account_iban,
                max(bp.created_at) AS last_payment_date
            FROM bank_payment AS bp
            GROUP BY bp.bank_account_iban
        ) bp ON ba.iban = bp.bank_account_iban
        WHERE last_payment_date IS NOT NULL
        GROUP BY ba.client_company_id, last_payment_date
        ORDER BY ba.client_company_id, last_payment_date DESC
    ) AS tb6 ON tb0.client_company_id = tb6.client_company_id
    LEFT JOIN (
        SELECT
            ccf.client_company_id  AS client_company_id,
            ccf.active             AS bludelta_sync_active
        FROM private.client_company_feature AS ccf
        LEFT JOIN private.feature AS feat ON ccf.feature_id = feat.id
        WHERE feat.name = 'BLUDELTA_EXTRACTION' -- TODO feature not used anymore, replace with public.client_company.custom_extraction_service
    ) AS tb8 ON tb0.client_company_id = tb8.client_company_id;
