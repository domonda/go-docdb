\echo
\echo '=== schema/public_after_automation.sql ==='
\echo

\ir public/document_history.sql
\ir public/activity_log.sql

\ir public/wizard_workflow_and_approvals.sql
\ir public/wizard_workflow_and_approvals_create.sql

\ir public/protected_document_workflow_step.sql

\ir public/unused_partner_companies.sql