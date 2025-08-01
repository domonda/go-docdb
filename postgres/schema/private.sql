\echo
\echo '=== schema/private.sql ==='
\echo

\ir private/bludelta2.sql
\ir private/docvibe.sql
\ir private/invoice.sql
\ir private/document_workflow_step_log.sql
\ir private/document_version_bludelta_data.sql
\ir private/feature.sql
\ir private/merge_transactions.sql
\ir private/op_health_check.sql
\ir private/client_company_api_sync.sql
\ir private/fluks_subscription.sql
\ir private/notification.sql
\ir private/session.sql
\ir private/blocked_api_key.sql

-- custom jobs
\ir private/convert_document_tags_to_invoice_paid_dates.sql
