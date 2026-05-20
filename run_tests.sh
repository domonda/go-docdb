#!/bin/bash

set -eou pipefail

# given
export $(cat .env.example | xargs)
docker compose up -d --wait
./storeconn/pgstore/init.sh
exit_code=0

# when
echo ""
echo "Running tests..."
( \
    go test ./proxyconn -count 1 \
    && go test ./localfsdb -count 1 \
    && go test ./storeconn/pgstore -count 1 \
    && go test ./storeconn/s3store -count 1 \
    && go test ./integrationtests -count 1
) || exit_code=$?
echo ""

# then
docker compose down -v
exit $exit_code
