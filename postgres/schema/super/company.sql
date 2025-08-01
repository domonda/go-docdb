create function super.dump_company(
  company_id uuid
) returns json
language sql stable strict as $$
  select jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'brandName', c.brand_name,
    'legalForm', c.legal_form,
    'founded', c.founded,
    'dissolved', c.dissolved,
    'locations', (
      select json_agg(jsonb_build_object(
        'id', cl.id,
        'companyId', cl.company_id,
        'partnerCompanyId', cl.partner_company_id,
        'createdBy', cl.created_by,
        'main', cl.main,
        'street', cl.street,
        'city', cl.city,
        'zip', cl.zip,
        'country', cl.country,
        'phone', cl.phone,
        'email', cl.email,
        'website', cl.website,
        'registrationNo', cl.registration_no,
        'taxIdNo', cl.tax_id_no,
        'vatIdNo', cl.vat_id_no,
        'updatedAt', updated_at,
        'createdAt', created_at
      )) from public.company_location as cl where cl.company_id = c.id
    ),
    'clientCompany', (
      select jsonb_build_object(
        'companyId', cc.company_id,
        'language', cc.language,
        'branding', cc.branding,
        'emailAlias', cc.email_alias,
        'billedClientCompanyId', cc.billed_client_company_id,
        'importMembers', cc.import_members,
        'customExtractionService', cc.custom_extraction_service,
        'accountingCurrency', cc.accounting_currency,
        'accountingEmail', cc.accounting_email,
        'accountingCompanyClientCompanyId', cc.accounting_company_client_company_id,
        'accountingSystem', cc.accounting_system,
        'accountingSystemClientNo', cc.accounting_system_client_no,
        'accountingExportDestUrl', cc.accounting_export_dest_url,
        'taxReclaimable', cc.tax_reclaimable,
        'vatDeclaration', cc.vat_declaration,
        'processing', cc.processing,
        'chartOfAccounts', cc.chart_of_accounts,
        'glNumberLength', cc.gl_number_length,
        'partnerNumberLength', cc.partner_number_length,
        'contractStartDate', cc.contract_start_date,
        'contractNote', cc.contract_note,
        'licensedDocuments', cc.licensed_documents,
        'licensedUsers', cc.licensed_users,
        'licensedBanks', cc.licensed_banks,
        'contractExpiryNotificationEmail', cc.contract_expiry_notification_email,
        'pain008_payment_id', cc.pain008_payment_id,
        'blacklistPartnerVatIdNos', cc.blacklist_partner_vat_id_nos,
        'notes', cc.notes,
        'appendAuditTrail', cc.append_audit_trail,
        'invoiceCostCenters', cc.invoice_cost_centers,
        'accountingItemCostCenters', cc.accounting_item_cost_centers,
        'invoiceCostUnits', cc.invoice_cost_units,
        'accountingItemCostUnits', cc.accounting_item_cost_units,
        'abandonedDocumentsWarning', cc.abandoned_documents_warning,
        'createPartner', cc.create_partner,
        'createPartnerAccount', cc.create_partner_account,
        'bmdBankinfo', cc.bmd_bankinfo,
        'restrictBookingExport', cc.restrict_booking_export,
        'disableIncompleteExport', cc.disable_incomplete_export,
        'disableReviewWorkflowManage', cc.disable_review_workflow_manage,
        'disableUnverifiedIbanCheck', cc.disable_unverified_iban_check,
        'invoiceInternalNumberCountUpMode', cc.invoice_internal_number_count_up_mode,
        'invoiceInternalNumberMin', cc.invoice_internal_number_min,
        'disableInvoiceInternalNumberEdit', cc.disable_invoice_internal_number_edit,
        'restrictDocumentDelete', cc.restrict_document_delete,
        'assignProtectedDocumentCategory', cc.assign_protected_document_category,
        'ibans', cc.ibans,
        'skipMatchingCheckIds', cc.skip_matching_check_ids,
        'customPaymentReminderMessage', cc.custom_payment_reminder_message,
        'factorBankCustomerNumber', cc.factor_bank_customer_number
      ) || jsonb_build_object(
        'statusHistory', (
          select json_agg(jsonb_build_object(
            'clientCompanyId', ccs.client_company_id,
            'status', ccs.status,
            'validFrom', to_char(ccs.valid_from, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
          )) from private.client_company_status as ccs where ccs.client_company_id = c.id
        ),
        'accountingCompany', (
          select jsonb_build_object(
            'clientCompanyId', ac.client_company_id,
            'isTaxAdviser', ac.is_tax_adviser,
            'active', ac.active,
            'updatedAt', updated_at,
            'createdAt', created_at
          ) from public.accounting_company as ac where ac.client_company_id = c.id
        ),
        'documentCategories', (
          select json_agg(jsonb_build_object(
            'id', dc.id,
            'clientCompanyId', dc.client_company_id,
            'documentType', dc.document_type,
            'bookingType', dc.booking_type,
            'bookingCategory', dc.booking_category,
            'description', dc.description,
            'emailAlias', dc.email_alias,
            'customExtractionService', dc.custom_extraction_service,
            'sortIndex', dc.sort_index,
            'generalLedgerAccountId', dc.general_ledger_account_id,
            'internalNumberMode', dc.internal_number_mode,
            'internalNumberMin', dc.internal_number_min,
            'accountingItemsGeneralLedgerAccountId', dc.accounting_items_general_ledger_account_id,
            'accountingItemsTitle', dc.accounting_items_title,
            'updatedAt', updated_at,
            'createdAt', created_at
          )) from public.document_category as dc where dc.client_company_id = c.id
        ),
        'generalLedgerAccounts', (
          select json_agg(jsonb_build_object(
            'id', gla.id,
            'clientCompanyId', gla.client_company_id,
            'number', gla.number,
            'currency', gla.currency,
            'name', gla.name,
            'category', gla.category,
            'updatedAt', updated_at,
            'createdAt', created_at
          )) from public.general_ledger_account as gla where gla.client_company_id = c.id
        ),
        'costCenters', (
          select json_agg(jsonb_build_object(
            'id', cccc.id,
            'clientCompanyId', cccc.client_company_id,
            'number', cccc.number,
            'description', cccc.description,
            'historic', cccc.historic::timestamptz,
            'currency', cccc.currency,
            'updatedAt', updated_at,
            'createdAt', created_at
          )) from public.client_company_cost_center as cccc where cccc.client_company_id = c.id
        ),
        'costUnits', (
          select json_agg(jsonb_build_object(
            'id', cccu.id,
            'clientCompanyId', cccu.client_company_id,
            'number', cccu.number,
            'description', cccu.description,
            'historic', cccu.historic::timestamptz,
            'currency', cccu.currency,
            'updatedAt', updated_at,
            'createdAt', created_at
          )) from public.client_company_cost_unit as cccu where cccu.client_company_id = c.id
        ),
        'tags', (
          select json_agg(jsonb_build_object(
            'id', cct.id,
            'clientCompanyId', cct.client_company_id,
            'tag', cct.tag,
            'updatedAt', updated_at,
            'createdAt', created_at
          )) from public.client_company_tag as cct where cct.client_company_id = c.id
        ),
        'documentWorkflows', (
          select json_agg(jsonb_build_object(
            'id', dw.id,
            'clientCompanyId', dw.client_company_id,
            'name', dw.name,
            'isAutomatic', dw.is_automatic,
            'steps', (
              select json_agg(jsonb_build_object(
                'id', dws.id,
                'workflowId', dws.workflow_id,
                'index', dws.index,
                'name', dws.name,
                'updatedAt', updated_at,
                'createdAt', created_at
              )) from public.document_workflow_step as dws where dws.workflow_id = dw.id
            ),
            'updatedAt', updated_at,
            'createdAt', created_at
          )) from public.document_workflow as dw where dw.client_company_id = c.id
        ),
        'updatedAt', updated_at,
        'createdAt', created_at
      ) from public.client_company as cc where cc.company_id = c.id
    ),
    'updatedAt', updated_at,
    'createdAt', created_at
  ) from public.company as c where c.id = dump_company.company_id
$$;
