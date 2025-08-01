begin;

\ir tests/matching.sql
\ir tests/invoice_accounting_item_suggestions.sql

\echo
\echo 'Rolling back test changes...'
rollback;
