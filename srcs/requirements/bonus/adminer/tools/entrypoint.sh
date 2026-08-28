#!/bin/sh
set -eu

echo "[entrypoint] Starting Adminer on :8080 (database host: mariadb) ..."

# PHP's built-in server, which is what the official Adminer image runs too.
# It keeps this to ONE process — adding nginx here to front a php-fpm pool
# would put two daemons in a container for a single-file admin page.
#
# exec: php is PID 1.
exec php -S 0.0.0.0:8080 -t /var/www/adminer
