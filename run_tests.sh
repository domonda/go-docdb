#!/bin/bash

set -eou pipefail

# given
# The suite needs Docker for the Postgres and MinIO services and psql to load
# the schema. Both are preinstalled on GitHub-hosted Ubuntu runners; say which
# one is missing instead of failing later with a cryptic error.
for cmd in docker psql; do
    if ! command -v "$cmd" >/dev/null; then
        echo "run_tests.sh needs '$cmd' but it is not installed" >&2
        exit 1
    fi
done

export $(cat .env.example | xargs)
docker compose up -d --wait
./storeconn/pgstore/init.sh
exit_code=0

# when
echo ""
echo "Running tests..."
# -p 1 runs one package at a time: the s3store and integrationtests packages
# share the single bucket of the MinIO service and the single Postgres database,
# and each clears its bucket, so running them concurrently makes them delete
# each other's objects.
( \
    go test ./... -count 1 -p 1
) || exit_code=$?
echo ""

# then
docker compose down -v
exit $exit_code
