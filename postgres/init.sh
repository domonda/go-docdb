#!/usr/bin/env bash
set -eou pipefail

base_dir="$(realpath "$(dirname "$0")")"
schema_dir="${base_dir}/schema"

export PGPASSWORD="${POSTGRES_PASSWORD}"

psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -h "${POSTGRES_HOST-127.0.0.1}" -p "${POSTGRES_PORT-5432}" <<-EOSQL
BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE schema docdb;
\ir $schema_dir/document_version.sql
\ir $schema_dir/document_version_file.sql
\ir $schema_dir/lock.sql

COMMIT;
EOSQL

echo ""
echo "Database initialization done!"
