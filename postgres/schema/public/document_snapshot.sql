create function public.document_snapshot(
  document public.document
) returns jsonb as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', document.id, -- required: pkg/notification/documentinfo.go
    'documentUrl', 'https://domonda.app/documents/' || document.id::text,

    'documentVersion', (select jsonb_build_object( -- wont exist for non checked in documents
        'id', document_version.id,
        'version', to_char(document_version.version, 'YYYY-MM-DD_HH24-MI-SS.MS')) -- Format as in domonda/go-docdb/versiontime.go
      from docdb.document_version
      where document_version.document_id = document.id
      order by document_version.version desc
      limit 1), -- required: pkg/notification/documentinfo.go
    'status', public.document_state(document),
    'title', public.document_derived_title(document), -- required: pkg/notification/documentinfo.go

    'company', (select jsonb_build_object(
        'id', company.id, -- required: pkg/notification/documentinfo.go
        'name', public.company_brand_name_or_name(company))
      from public.company
      where company.id = document.client_company_id),

    'importedAt', document.import_date,

    -- TODO-db-211022 might expose internals, up for discussion
    -- 'importedBy', (select jsonb_build_object(
    --     'id', "user".id,
    --     'fullName', public.user_full_name("user"),
    --     'email', "user".email)
    --   from public."user"
    --   where "user".id = document.imported_by),

    -- TODO-db-211022 might expose internals, up for discussion
    -- 'source', document.source,

    'category', (select jsonb_build_object(
        'id', document_category.id,
        'documentType', document_category.document_type,
        'bookingType', document_category.booking_type,
        'bookingCategory', document_category.booking_category,
        'description', document_category.description,
        'emailAlias', document_category.email_alias)
      from public.document_category
      where document_category.id = document.category_id),

    'invoice', (select jsonb_build_object(
        'id', invoice.document_id,
        'internalNumber', invoice.internal_number,
        'invoiceDate', invoice.invoice_date,
        'invoiceNumber', invoice.invoice_number,
        'total', invoice.total,
        'net', invoice.net,
        'vatAmount', public.invoice_vat_amount(invoice),
        'creditMemo', invoice.credit_memo,
        'currency', invoice.currency,
        'conversionRate', invoice.conversion_rate,
        'orderNumber', invoice.order_number,
        'orderDate', invoice.order_date,
        'deliveredFrom', invoice.delivered_from,
        'deliveredUntil', invoice.delivered_until,
        'paymentStatus', invoice.payment_status,
        'paymentPaidDate', public.invoice_payment_paid_date(invoice),
        -- 'paidDate', invoice.paid_date,
        'paymentCurrency', public.invoice_payment_currency(invoice),
        'paymentDueDate', public.invoice_payment_due_date(invoice),
        -- 'dueDate', invoice.due_date
        'paymentDiscountDueDate', public.invoice_payment_discount_due_date(invoice),
        -- 'discountDueDate', invoice.discount_until
        'paymentDiscountPercent', public.invoice_payment_discount_percent(invoice),
        -- 'discountPercent', invoice.discount_percent
        'paymentDiscountAmount', public.invoice_payment_discount_amount(invoice),
        -- 'discountAmount', invoice.discount_amount
        'paymentIban', public.invoice_payment_iban(invoice),
        -- 'iban', invoice.iban
        'paymentBic', public.invoice_payment_bic(invoice),
        -- 'bic', invoice.bic
        'partiallyPaid', invoice.partially_paid,

        'partnerCompany', (select jsonb_build_object(
          'id', partner_company.id,
          'name', partner_company.derived_name,
          'location', (select jsonb_build_object(
            'id', company_location.id,
            'street', company_location.street,
            'city', company_location.city,
            'zip', company_location.zip,
            'country', company_location.country,
            'phone', company_location.phone,
            'email', company_location.email,
            'website', company_location.website,
            'registration_no', company_location.registration_no,
            'tax_id_no', company_location.tax_id_no,
            'vat_id_no', company_location.vat_id_no)
          from public.company_location
          where company_location.id = invoice.partner_company_location_id))
        from public.partner_company
        where partner_company.id = invoice.partner_company_id))
      from public.invoice
      where invoice.document_id = document.id),

    'otherDocument', (select jsonb_build_object(
        -- TODO-db-211021
        'otherDocumentId', other_document.document_id)
      from public.other_document
      where other_document.document_id = document.id),

      -- TODO-db-211021 public.delivery_note
      -- TODO-db-211021 public.document_history

    'createdAt', now()
  ))
$$ language sql stable strict;

comment on function public.document_snapshot is '@notNull';
