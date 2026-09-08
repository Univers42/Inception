#!/bin/hellish
set -eu

echo "[entrypoint] Starting static-site NGINX ..."
exec nginx -g "daemon off;"
