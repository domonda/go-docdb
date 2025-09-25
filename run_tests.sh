#!/bin/bash

set -eou pipefail

# given
export $(cat .env.example | xargs)
docker compose up -d --wait
./postgres/init.sh
exit_code=0

# when
go test ./... -count 1 || exit_code=$?

# then
docker compose down -v
exit $exit_code
