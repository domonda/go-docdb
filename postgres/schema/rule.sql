\echo
\echo '=== schema/rule.sql ==='
\echo

\ir rule/document_ready.sql

\ir rule/special_user.sql

\ir rule/action.sql
\ir rule/reaction.sql
\ir rule/action_reaction.sql
\ir rule/operators.sql
-- send_mail_document_workflow_changed
\ir rule/send_mail_document_workflow_changed_reaction.sql
\ir rule/send_mail_document_workflow_changed_log.sql
-- send_notification
\ir rule/send_notification_reaction.sql
\ir rule/send_notification_log.sql
-- document_category
\ir rule/document_category_id_condition.sql
\ir rule/document_category_document_type_condition.sql
\ir rule/document_category_check.sql
-- document
\ir rule/document_condition.sql
\ir rule/document_import_date_condition.sql
\ir rule/document_client_company_tag_condition.sql
\ir rule/document_document_workflow_step_condition.sql
\ir rule/document_approval_condition.sql
\ir rule/document_real_estate_object_condition.sql
\ir rule/document_check.sql
\ir rule/document_reaction.sql
\ir rule/document_log.sql
-- document macro
\ir rule/document_macro_condition.sql
\ir rule/document_macro_check.sql
\ir rule/document_macro_reaction.sql
\ir rule/document_macro_log.sql
-- invoice
\ir rule/invoice_condition.sql
\ir rule/invoice_completeness_level_condition.sql
\ir rule/invoice_partner_company_condition.sql
\ir rule/invoice_total_condition.sql
\ir rule/invoice_invoice_date_condition.sql
\ir rule/invoice_cost_center_condition.sql
\ir rule/invoice_cost_unit_condition.sql
\ir rule/invoice_check.sql
\ir rule/invoice_reaction.sql
\ir rule/invoice_log.sql
-- document_approval
\ir rule/document_approval_request_reaction.sql
\ir rule/document_approval_request_log.sql
-- cancel_document_approval
\ir rule/cancel_document_approval_request_reaction.sql
\ir rule/cancel_document_approval_request_log.sql
-- document_tag
\ir rule/document_tag_reaction.sql
\ir rule/document_tag_log.sql
-- cloning
\ir rule/clone_action.sql
\ir rule/clone_reaction.sql
\ir rule/clone_actions_reactions_to_client_company.sql
-- after all
\ir rule/action_reaction_after_all.sql
-- filters
\ir rule/filter_actions.sql
\ir rule/filter_reactions.sql
\ir rule/filter_actions_reactions.sql
-- trigger
\ir rule/trigger.sql
