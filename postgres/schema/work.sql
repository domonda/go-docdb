\echo
\echo '=== schema/work.sql ==='
\echo

\ir work/rights.sql
\ir work/group.sql
\ir work/group_user.sql
\ir work/group_document.sql
\ir work/group_chat.sql
\ir work/group_log.sql

\ir work/space.sql
\ir work/space_user.sql
\ir work/space_log.sql

-- \ir work/external_org.sql

\ir work/share_document.sql

\ir work/triggers.sql

-- access control
\ir work/user_policies.sql
\ir work/client_company_policies.sql
\ir work/document_category_policies.sql
\ir work/document_policies.sql
\ir work/document_comment_policies.sql
\ir work/review_group_policies.sql
\ir work/control_client_company_user_policies.sql
