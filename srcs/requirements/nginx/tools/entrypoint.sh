#!/bin/sh
set -eu

: "${DOMAIN_NAME:?DOMAIN_NAME is required}"
CERTS_CRT="${CERTS_CRT:-/etc/nginx/ssl/inception.crt}"
CERTS_KEY="${CERTS_KEY:-/etc/nginx/ssl/inception.key}"

mkdir -p "$(dirname "$CERTS_CRT")" "$(dirname "$CERTS_KEY")"
cp /run/secrets/server_crt "$CERTS_CRT"
cp /run/secrets/server_key "$CERTS_KEY"
chmod 644 "$CERTS_CRT"
chmod 600 "$CERTS_KEY"

sed -e "s|\${DOMAIN_NAME}|${DOMAIN_NAME}|g" \
    -e "s|\${CERTS_CRT}|${CERTS_CRT}|g" \
    -e "s|\${CERTS_KEY}|${CERTS_KEY}|g" \
    /etc/nginx/http.d/default.conf.template \
    > /etc/nginx/http.d/default.conf

echo "[entrypoint] Starting NGINX ..."
exec nginx -g "daemon off;"
