#!/bin/bash

set -eou pipefail

# given
export $(cat .env.example | xargs)
docker compose up -d --wait
./postgres/init.sh
exit_code=0

# when
( \
    go test ./postgres -count 1 \
    && go test ./s3 -count 1 \
    && go test ./integrationtests -count 1 \
) || exit_code=$?

# then
docker compose down -v
exit $exit_code
