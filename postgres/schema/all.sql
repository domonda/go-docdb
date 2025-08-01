BEGIN;

\ir schemas.sql
\ir public/types.sql

\ir worker.sql
\ir gql_subscription.sql

\ir public_w_matching.sql

\ir private.sql
\ir public_after_private.sql

\ir control.sql

-- helpers and identifiers for the current user/session
\ir current_after_control.sql
\ir public_after_control.sql

\ir super.sql

\ir object/schema.sql
\ir public/real_estate_object.sql
\ir public/real_estate_object_tenant_owner.sql
\ir private/find_object_on_document.sql
\ir private/find_real_estate_object.sql
\ir public/filter_general_ledger_accounts.sql
\ir public/document_category_object_instance.sql
\ir public/signa_company.sql

\ir rule.sql -- legacy
\ir automation.sql

\ir public_after_automation.sql

\ir public/dashboard.sql
\ir public/dashboard_todos.sql
\ir api.sql
-- \ir docdb.sql
\ir work.sql

\ir monitor.sql

COMMIT;
