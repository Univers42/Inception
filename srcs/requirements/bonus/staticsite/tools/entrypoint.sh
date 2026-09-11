#!/bin/hellish
# shellcheck shell=sh
set -eu

echo "[entrypoint] Starting static-site NGINX ..."
exec nginx -g "daemon off;"
