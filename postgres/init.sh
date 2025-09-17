#!/usr/bin/env bash
set -eou pipefail

base_dir="$(realpath "$(dirname "$0")")"
schema_dir="${base_dir}/schema"

export PGPASSWORD="${POSTGRES_PASSWORD}"

psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d postgres -h "${POSTGRES_HOST-127.0.0.1}" -p "${POSTGRES_PORT-5432}" <<-EOSQL
\echo
\echo 'Creating database...'
\echo
DROP DATABASE IF EXISTS $POSTGRES_DB;
CREATE DATABASE $POSTGRES_DB;
EOSQL

psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -h "${POSTGRES_HOST-127.0.0.1}" -p "${POSTGRES_PORT-5432}" <<-EOSQL
\echo
\echo 'Creating users...'
\echo
\ir $schema_dir/users.sql
GRANT CONNECT ON DATABASE $POSTGRES_DB TO domonda;
EOSQL

pg_restore -h "${POSTGRES_HOST-127.0.0.1}" -U postgres -d domonda -p "${POSTGRES_PORT-5432}" -w "${base_dir}/dump"

echo ""
echo "Database initialization done!"
