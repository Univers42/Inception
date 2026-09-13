#!/bin/hellish
# shellcheck shell=sh
#
# srcs/requirements/bonus/api/tools/entrypoint.sh
# Validate the environment, check the secret is mounted, wait for both backends
# with a bounded TCP probe, then hand PID 1 to node.
set -eu

: "${API_DB_HOST:?API_DB_HOST is required}"
: "${API_DB_PORT:=3306}"
: "${API_DB_NAME:?API_DB_NAME is required}"
: "${API_DB_USER:?API_DB_USER is required}"
: "${API_REDIS_HOST:?API_REDIS_HOST is required}"
: "${API_REDIS_PORT:=6379}"

[ -s /run/secrets/api_db_password ] || {
    echo "[entrypoint] ERROR: /run/secrets/api_db_password is missing or empty" >&2
    exit 1
}

# wait_for <host> <port> <label> <seconds>: one TCP connect per second, then
# give up with a clear message. The server has its own backoff for the
# handshake; this only spares it from a burst of connection-refused noise.
wait_for() {
    i=0
    while ! nc -z -w 1 "$1" "$2" 2>/dev/null; do
        i=$((i + 1))
        if [ "$i" -ge "$4" ]; then
            echo "[entrypoint] ERROR: $3 ($1:$2) did not accept connections within $4 s" >&2
            exit 1
        fi
        sleep 1
    done
    echo "[entrypoint] $3 is accepting connections ($1:$2, waited ${i}s)"
}

wait_for "$API_DB_HOST"    "$API_DB_PORT"    mariadb 90
wait_for "$API_REDIS_HOST" "$API_REDIS_PORT" redis   30

echo "[entrypoint] Starting the lab API ..."
exec node /app/server.js
