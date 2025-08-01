\echo
\echo '=== schema/public_after_control.sql ==='
\echo

\ir public/document_approval_after_control.sql
-- \ir public/document_value_confirmation.sql
\ir public/user_activity_log.sql
\ir public/filter_client_companies.sql
\ir public/user_default.sql
\ir public/user_acl.sql
\ir public/document_workflow_step_after_control.sql
\ir public/document_payment_status.sql
\ir public/partner_company_balance.sql
\ir public/email.sql
\ir public/email_attachment.sql
\ir public/client_company_after_control.sql
