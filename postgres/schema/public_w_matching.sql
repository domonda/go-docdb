\echo
\echo '=== schema/public.sql ==='
\echo

\ir public/currency_rate.sql
\ir public/functions.sql
\ir public/company.sql
\ir public/company_name_search.sql
\ir public/accounting_company.sql
\ir public/client_company.sql
\ir public/user.sql
-- helpers and identifiers for the current user/session
\ir current.sql
\ir public/user_after_current.sql
\ir public/user_group.sql
\ir public/filter_user_groups.sql
\ir private/client_company_status.sql
\ir public/client_company_after_client_company_status.sql
\ir public/general_ledger_account.sql
\ir public/accounting_instruction.sql
\ir public/partner_company.sql
\ir public/company_location.sql
\ir public/company_and_main_location.sql
\ir public/merge_partner_company.sql
\ir public/partner_company_duplicate.sql
\ir public/client_company_domain_name.sql
\ir public/payment_package.sql
\ir public/value_added_tax.sql
\ir public/filter_value_added_taxes.sql
\ir public/demo_mode.sql
\ir public/sent_email.sql

\ir xs2a/bank_user.sql
\ir xs2a/connection.sql
\ir xs2a/account.sql

\ir public/document_workflow.sql
\ir public/document_workflow_step.sql
\ir public/find_document_workflow.sql
\ir public/document_type.sql
\ir public/booking_type.sql
\ir public/document_category.sql
\ir public/document_category_functions.sql
\ir public/filter_document_categories.sql
\ir public/document.sql

-- docdb tables depend on public.document and public.user
\ir docdb/document_version.sql
\ir docdb/document_version_file.sql
\ir docdb/lock.sql

\ir public/document_workflow_step_log.sql
\ir public/filter_document_workflows.sql
\ir public/filter_document_workflow_steps.sql

\ir matching/checks.sql
\ir matching/default_checks.sql
\ir matching/client_company_rule.sql
\ir matching/default_client_company_rule.sql

\ir public/money_category.sql
\ir public/bank.sql
\ir public/bank_account.sql
\ir public/bank_transaction.sql
\ir public/document_bank_transaction.sql
\ir public/credit_card_account.sql
\ir public/credit_card_transaction.sql
\ir public/document_credit_card_transaction.sql
\ir public/cash_account.sql
\ir public/cash_transaction.sql
\ir public/document_cash_transaction.sql
\ir public/paypal_account.sql
\ir public/paypal_transaction.sql
\ir public/document_paypal_transaction.sql
\ir public/stripe_account.sql
\ir public/stripe_transaction.sql
\ir public/document_stripe_transaction.sql
\ir public/bank_payment.sql
\ir public/money_account.sql
\ir public/money_transaction.sql
\ir public/document_money_transaction.sql

-- partner payment presets
\ir public/partner_company_payment_preset.sql

-- filter_money_transactions
\ir builder/filter_money_transactions_query.sql
\ir public/filter_money_transactions.sql
\ir public/deprecated_filter_money_transactions.sql

\ir xs2a/account_functions.sql
\ir xs2a/session.sql

\ir public/partner_account.sql
\ir public/filter_partner_accounts.sql
\ir public/invoice.sql
\ir public/invoice_completeness.sql
\ir public/invoice_subscription.sql
\ir public/invoice_item.sql
\ir public/delivery_note.sql
\ir public/delivery_note_item.sql
\ir public/invoice_accounting_item.sql
\ir public/journal_accounting_item.sql
\ir public/accounting_item.sql
\ir public/invoice_last_edit.sql
\ir public/other_document.sql

\ir public/document_fulltext.sql

\ir public/document_recurrence.sql

\ir public/update_invoice.sql
\ir public/update_other_document.sql

\ir matching/perform.sql
\ir matching/match_invoices.sql
\ir matching/match_transactions.sql

\ir public/money_export.sql
\ir public/money_export_money_transaction.sql
\ir public/money_export_functions.sql

\ir public/color_scheme.sql
\ir public/client_company_tag.sql
\ir public/filter_client_company_tags.sql
\ir public/document_tag.sql
\ir public/client_company_cost_center.sql
\ir public/invoice_cost_center.sql
\ir public/invoice_accounting_item_cost_center.sql
\ir public/client_company_cost_unit.sql
\ir public/invoice_cost_unit.sql
\ir public/invoice_accounting_item_cost_unit.sql
\ir public/invoice_partner_company_cost_centers_and_units.sql

\ir public/invoice_accounting_item_suggestions.sql
\ir public/invoice_accounting_item_after_suggestions.sql

\ir public/document_field.sql
\ir public/document_field_defaults.sql
\ir public/document_field_triggers.sql

-- public.review_group depends on docdb.lock
\ir public/review_group.sql
\ir public/review_group_document.sql
\ir public/document_log.sql
\ir public/review_group_subscription.sql
\ir public/sort_review_group.sql

-- public.source_file depends on public.review_group
\ir public/source_file.sql
\ir public/source_file_money_transactions.sql
\ir public/source_file_status.sql
\ir public/source_file_subscription.sql
\ir public/review_group_after_source_file.sql

\ir public/document_export.sql
\ir public/document_export_document.sql
\ir public/filter_document_exports.sql

-- filter_documents
\ir public/filter_documents_parts.sql
\ir builder/filter_documents_query.sql
\ir public/filter_documents.sql

\ir public/client_company_after_filter_documents.sql

-- export
\ir public/export.sql
\ir public/filter_exports.sql
\ir public/export_filename.sql

\ir public/document_state.sql
\ir public/invoice_delivery_note.sql
\ir public/document_functions.sql
\ir public/document_workflow_functions.sql
\ir public/filter_open_items.sql
\ir public/filesystem_import_rule.sql
\ir public/filter_companies.sql
\ir public/filter_accounting_companies.sql
\ir public/document_page_text.sql
\ir public/document_page.sql
\ir public/document_page_block.sql
\ir public/document_page_line.sql
\ir public/document_page_word.sql
\ir public/scanner.sql
\ir public/chargebee_invoice.sql
\ir public/filter_banks.sql
\ir public/filter_bank_accounts.sql
\ir public/filter_credit_card_accounts.sql
\ir public/filter_cash_accounts.sql
\ir public/pain001.sql
\ir public/pain008.sql
\ir public/filter_partner_companies.sql
\ir public/partner_company_open_items_stats.sql
\ir public/partner_company_open_items_stats_preset.sql
\ir public/billomat_config.sql
\ir public/fastbill_config.sql
\ir public/getmyinvoices_config.sql
\ir public/faktoora_config.sql
\ir public/ftp_sync_config.sql

\ir public/document_approval.sql

-- document comments
\ir public/document_comment.sql
\ir public/document_approval_after_document_comment.sql

\ir public/extension_request_email.sql

\ir public/document_snapshot.sql

\ir public/client_company_block.sql

\ir public/document_payment_reminder.sql

-- eu oss
\ir public/client_company_oss_branch.sql
