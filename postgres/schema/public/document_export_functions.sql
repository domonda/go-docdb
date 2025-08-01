CREATE FUNCTION public.create_document_export(
    -- options
    pdf_files         boolean,
    spreadsheets      boolean,
    bmd_invoices      boolean,
    bmd_bank          boolean,
    bmd_masterdata    boolean,
    dvo_invoices      boolean,
    im_factoring      boolean,
    booking_export    boolean,
    -- what
    client_company_id uuid,
    document_ids      uuid[]
) RETURNS public.document_export AS
$$
DECLARE
    document_export RECORD;
    document_id     uuid;
BEGIN
    -- check if there is something to export
    IF (COALESCE(array_length(create_document_export.document_ids, 1), 0) = 0) THEN
        RAISE EXCEPTION USING MESSAGE = 'no documents for exporting';
    END IF;

    -- check for booked documents
    IF create_document_export.booking_export THEN
        IF EXISTS(
            SELECT 1 FROM public.document_export_document AS ded
                INNER JOIN public.document_export AS de ON (de.id = ded.document_export_id)
            WHERE (
                de.booking_export = true
            ) AND (
                ded.document_id = ANY(create_document_export.document_ids)
            )
        ) THEN
            RAISE EXCEPTION USING MESSAGE = 'certain documents in the export set are already marked as booked';
        END IF;
    END IF;

    -- extra checks for im factoring exports
    IF create_document_export.im_factoring THEN

        -- check if invoice(s) is/are just outgoing
        IF EXISTS (
            SELECT 1 FROM public.invoice AS i
            INNER JOIN (
                public.document AS d
                    INNER JOIN public.document_category AS dc
                    ON (
                        dc.id = d.category_id
                        AND dc.document_type != 'OUTGOING_INVOICE'
                    )
            ) ON (d.id = i.document_id)
            WHERE (i.document_id = ANY(create_document_export.document_ids))
        ) THEN
            RAISE EXCEPTION USING MESSAGE = 'IMB Fullfactoring export doesn''t support incoming invoices.';
        END IF;

        -- check for missing invoice dates
        IF EXISTS (
            SELECT 1 FROM public.invoice AS i
            WHERE (
                i.document_id = ANY(create_document_export.document_ids)
            ) AND (
                i.invoice_date IS NULL
            )
        ) THEN
            RAISE EXCEPTION USING MESSAGE = 'Some invoices are missing invoice dates, they are required for IMB Fullfactoring export.';
        END IF;

        -- check for missing currencies
        IF EXISTS (
            SELECT 1 FROM public.invoice AS i
            WHERE (
                i.document_id = ANY(create_document_export.document_ids)
            ) AND (
                i.currency IS NULL
            )
        ) THEN
            RAISE EXCEPTION USING MESSAGE = 'Some invoices are missing currencies, they are required for IMB Fullfactoring export.';
        END IF;

        -- check for missing invoice partner account numbers
        IF EXISTS (
            SELECT 1 FROM
                public.invoice AS i,
                public.invoice_partner_account(i) AS pa
            WHERE (
                i.document_id = ANY(create_document_export.document_ids)
            ) AND (
                pa."number" IS NULL
            )
        ) THEN
            RAISE EXCEPTION USING MESSAGE = 'Some invoices are missing partner account numbers, they are required for IMB Fullfactoring export.';
        END IF;

        -- check for different currencies
        IF EXISTS (
            SELECT 1 FROM public.invoice AS i
            WHERE (
                i.document_id = ANY(create_document_export.document_ids)
            )
            HAVING count(distinct i.currency) != 1
        ) THEN
            RAISE EXCEPTION USING MESSAGE = 'IMB Fullfactoring export doesn''t support mixing of currencies';
        END IF;

    END IF;

    -- creating document_export row
    INSERT INTO public.document_export (
        id,
        client_company_id,
        user_id,
        pdf_files,
        spreadsheets,
        bmd_invoices,
        bmd_bank,
        bmd_masterdata,
        dvo_invoices,
        im_factoring,
        booking_export,
        created_at
    )
    VALUES (
        uuid_generate_v4(),
        create_document_export.client_company_id,
        curr_user_id,
        create_document_export.pdf_files,
        create_document_export.spreadsheets,
        create_document_export.bmd_invoices,
        create_document_export.bmd_bank,
        create_document_export.bmd_masterdata,
        create_document_export.dvo_invoices,
        create_document_export.im_factoring,
        create_document_export.booking_export,
        now()
    )
    RETURNING * INTO document_export;

    -- inserting documents into document_export_document
    FOREACH document_id IN ARRAY(create_document_export.document_ids) LOOP
        INSERT INTO public.document_export_document (document_export_id, document_id, document_version)
            SELECT document_export.id, d.id, d.version FROM public.document AS d WHERE (d.id = document_id);
    END LOOP;

    RETURN document_export;
END;
$$
LANGUAGE plpgsql VOLATILE;

----

CREATE FUNCTION public.create_document_export_from_filter(
    -- export
    pdf_files      boolean,
    spreadsheets   boolean,
    bmd_invoices   boolean,
    bmd_bank       boolean,
    bmd_masterdata boolean,
    dvo_invoices   boolean,
    im_factoring   boolean,
    booking_export boolean,
    -- filter
    client_company_id           uuid,
    document_category_ids       text[],
    date_filter_type            public.filter_documents_date_filter_type,
    from_date                   date,
    until_date                  date,
    search_text                 text,
    tags                        text[],
    superseded                  boolean,
    verified                    boolean,
    min_total                   float8,
    max_total                   float8,
    partner_names               text[],
    cost_center_ids             text[],
    workflow_ids                text[],
    workflow_step_ids           text[],
    export_status               public.filter_documents_export_status,
    export_user_ids             text[],
    paid_status                 public.filter_documents_paid_status,
    paid_with_money_account_ids uuid[]
) RETURNS public.document_export AS
$$
DECLARE
    document_export_ids     uuid[];
    document_export_id      uuid;
    document_export         RECORD;
    filter_documents_filter jsonb;
BEGIN
    -- get the array of documents to export
    SELECT
        array_agg(id) INTO document_export_ids
    FROM public.filter_documents(
        create_document_export_from_filter.client_company_id,
        create_document_export_from_filter.document_category_ids,
        create_document_export_from_filter.date_filter_type,
        create_document_export_from_filter.from_date,
        create_document_export_from_filter.until_date,
        create_document_export_from_filter.search_text,
        create_document_export_from_filter.tags,
        create_document_export_from_filter.superseded,
        create_document_export_from_filter.verified,
        create_document_export_from_filter.min_total,
        create_document_export_from_filter.max_total,
        create_document_export_from_filter.partner_names,
        create_document_export_from_filter.cost_center_ids,
        create_document_export_from_filter.workflow_ids,
        create_document_export_from_filter.workflow_step_ids,
        create_document_export_from_filter.export_status,
        create_document_export_from_filter.export_user_ids,
        create_document_export_from_filter.paid_status,
        create_document_export_from_filter.paid_with_money_account_ids
    );

    -- create the export
    SELECT id INTO document_export_id FROM public.create_document_export(
        -- options
        create_document_export_from_filter.pdf_files,
        create_document_export_from_filter.spreadsheets,
        create_document_export_from_filter.bmd_invoices,
        create_document_export_from_filter.bmd_bank,
        create_document_export_from_filter.bmd_masterdata,
        create_document_export_from_filter.dvo_invoices,
        create_document_export_from_filter.im_factoring,
        create_document_export_from_filter.booking_export,
        -- what
        create_document_export_from_filter.client_company_id,
        document_export_ids
    );

    -- create the filter
    filter_documents_filter := jsonb_build_object(
        'clientCompanyId', client_company_id,
        'documentCategoryIds', document_category_ids,
        'dateFilterType', date_filter_type,
        'fromDate', from_date,
        'untilDate', until_date,
        'searchText', search_text,
        'tags', tags,
        'superseded', superseded,
        'verified', verified,
        'minTotal', min_total,
        'maxTotal', max_total,
        'partnerNames', partner_names,
        'costCenterIds', cost_center_ids,
        'workflowIds', workflow_ids,
        'workflowStepIds', workflow_step_ids,
        'exportStatus', export_status,
        'exportUserIds', export_user_ids,
        'paidStatus', paid_status,
        'paidWithMoneyAccountIds', paid_with_money_account_ids
    );

    -- update the export by setting the filter
    SELECT
        * INTO document_export
    FROM private.set_document_export_filter(document_export_id, filter_documents_filter);

    RETURN document_export;
END;
$$
LANGUAGE plpgsql VOLATILE;
