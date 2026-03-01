#!/bin/sh
set -e

# ── Generate self-signed TLS certificate on first run ────────────────
# ECDSA P-256: faster handshake & smaller cert than RSA-2048
if [ ! -f "${CERTS_CRT}" ]; then
    echo "[entrypoint] Generating ECDSA self-signed TLS certificate …"
    openssl ecparam -genkey -name prime256v1 -out "${CERTS_KEY}" 2>/dev/null
    openssl req -new -x509 -nodes -days 365 \
        -key  "${CERTS_KEY}" \
        -out  "${CERTS_CRT}" \
        -subj "/C=FR/ST=IDF/L=Paris/O=42/OU=42/CN=${DOMAIN_NAME}"
fi

# ── Render nginx config template (only substitute OUR variables) ─────
envsubst '${DOMAIN_NAME} ${CERTS_CRT} ${CERTS_KEY}' \
    < /etc/nginx/http.d/default.conf.template \
    > /etc/nginx/http.d/default.conf

echo "[entrypoint] Starting NGINX …"
exec nginx -g "daemon off;"
