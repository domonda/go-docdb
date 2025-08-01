\echo
\echo '=== schema/control.sql ==='
\echo

-- TODO: implement policies for: document_filter, document_category_access, document_workflow_access and document_workflow_step_access

-- users
\ir control/client_company_user.sql
-- filters
\ir control/document_filter.sql
-- access
\ir control/document_category_access.sql
\ir control/document_workflow_access.sql
\ir control/document_workflow_step_access.sql
-- policies
\ir control/user_policy.sql
\ir control/client_company_user_policy.sql
\ir control/client_company_policy.sql
\ir control/document_category_policy.sql
\ir control/document_comment_policy.sql
\ir control/document_workflow_policy.sql
\ir control/document_workflow_step_policy.sql
\ir control/document_policy.sql
\ir control/review_group_policy.sql
\ir control/xs2a_bank_user_policy.sql
\ir control/xs2a_account_policy.sql
\ir control/xs2a_connection_policy.sql
-- functions
\ir control/functions.sql
-- hidden control functions which domonda_user can run
\ir private/control.sql
-- other
\ir control/user.sql
\ir public/filter_users.sql
\ir control/filter_client_company_users.sql
\ir control/clone_client_company_users_to_client_company.sql
