create function public.update_other_document(
  document_id uuid,
  "type" public.other_document_type,
  partner_company_id uuid = null,
  document_date date = null,
  document_number non_empty_text = null,
  document_details non_empty_text = null,
  resubmission_date date = null,
  expiry_date date = null,
  contract_type public.other_document_contract_type = null,
  contact_user_id uuid = null
) returns public.other_document as $$
  update public.other_document
    set
      ("type", type_changed_by, type_changed_at) = (
        select val::public.other_document_type, conf_by::uuid, conf_at from private.calc_invoice_value_fields(
          update_other_document."type"::text,
          "type"::text,
          type_changed_by::text,
          type_changed_at
        )
      ),
      (partner_company_id, partner_company_id_changed_by, partner_company_id_changed_at) = (
        select val::uuid, conf_by::uuid, conf_at from private.calc_invoice_value_fields(
          update_other_document.partner_company_id::text,
          partner_company_id::text,
          partner_company_id_changed_by::text,
          partner_company_id_changed_at
        )
      ),
      (document_date, document_date_changed_by, document_date_changed_at) = (
        select val::date, conf_by::uuid, conf_at from private.calc_invoice_value_fields(
          update_other_document.document_date::text,
          document_date::text,
          document_date_changed_by::text,
          document_date_changed_at
        )
      ),
      (document_number, document_number_changed_by, document_number_changed_at) = (
        select val::non_empty_text, conf_by::uuid, conf_at from private.calc_invoice_value_fields(
          update_other_document.document_number::text,
          document_number::text,
          document_number_changed_by::text,
          document_number_changed_at
        )
      ),
      (document_details, document_details_changed_by, document_details_changed_at) = (
        select val::non_empty_text, conf_by::uuid, conf_at from private.calc_invoice_value_fields(
          update_other_document.document_details::text,
          document_details::text,
          document_details_changed_by::text,
          document_details_changed_at
        )
      ),
      (resubmission_date, resubmission_date_changed_by, resubmission_date_changed_at) = (
        select val::date, conf_by::uuid, conf_at from private.calc_invoice_value_fields(
          update_other_document.resubmission_date::text,
          resubmission_date::text,
          resubmission_date_changed_by::text,
          resubmission_date_changed_at
        )
      ),
      (expiry_date, expiry_date_changed_by, expiry_date_changed_at) = (
        select val::date, conf_by::uuid, conf_at from private.calc_invoice_value_fields(
          update_other_document.expiry_date::text,
          expiry_date::text,
          expiry_date_changed_by::text,
          expiry_date_changed_at
        )
      ),
      (contract_type, contract_type_changed_by, contract_type_changed_at) = (
        select val::public.other_document_contract_type, conf_by::uuid, conf_at from private.calc_invoice_value_fields(
          update_other_document.contract_type::text,
          contract_type::text,
          contract_type_changed_by::text,
          contract_type_changed_at
        )
      ),
      (contact_user_id, contact_user_id_changed_by, contact_user_id_changed_at) = (
        select val::uuid, conf_by::uuid, conf_at from private.calc_invoice_value_fields(
          update_other_document.contact_user_id::text,
          contact_user_id::text,
          contact_user_id_changed_by::text,
          contact_user_id_changed_at
        )
      ),
      updated_at=now()
  where other_document.document_id = update_other_document.document_id
  returning *
$$ language sql volatile;
