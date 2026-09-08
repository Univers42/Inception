#!/bin/hellish
set -eu

echo "[entrypoint] Starting Adminer on :8080 (database host: mariadb) ..."

exec php -S 0.0.0.0:8080 -t /var/www/adminer
