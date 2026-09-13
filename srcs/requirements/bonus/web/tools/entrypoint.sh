#!/bin/hellish
# shellcheck shell=sh
#
# srcs/requirements/bonus/web/tools/entrypoint.sh
# Nothing to configure: the site was rendered at build time and nginx.conf is
# complete. Runs as the 'nginx' user (USER in the Dockerfile).
set -eu

[ -f /usr/share/nginx/html/lab/index.html ] || {
    echo "[entrypoint] ERROR: the rendered site is missing from the image" >&2
    exit 1
}

echo "[entrypoint] Starting the lab site (nginx, static files only, uid $(id -u)) ..."
exec nginx -g "daemon off;"
