#!/bin/sh
set -e

CA_KEY="/run/secrets/ca_key"
CA_CRT="/run/secrets/ca_crt"

# ── Generate server certificate signed by local CA ───────────────────
if [ ! -f "${CERTS_CRT}" ]; then
    echo "[entrypoint] Generating server certificate signed by local CA …"

    # Generate server ECDSA key
    openssl ecparam -genkey -name prime256v1 -out "${CERTS_KEY}" 2>/dev/null

    # Create CSR
    openssl req -new \
        -key  "${CERTS_KEY}" \
        -out  /tmp/server.csr \
        -subj "/C=FR/ST=IDF/L=Paris/O=42/OU=42/CN=${DOMAIN_NAME}"

    # Create SAN extension file
    cat > /tmp/san.cnf <<-EOF
		authorityKeyIdentifier=keyid,issuer
		basicConstraints=CA:FALSE
		keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment
		subjectAltName=@alt_names
		[alt_names]
		DNS.1=${DOMAIN_NAME}
		DNS.2=localhost
		IP.1=127.0.0.1
	EOF

    # Sign with CA
    openssl x509 -req -days 365 \
        -in      /tmp/server.csr \
        -CA      "${CA_CRT}" \
        -CAkey   "${CA_KEY}" \
        -CAcreateserial \
        -out     "${CERTS_CRT}" \
        -extfile /tmp/san.cnf 2>/dev/null

    rm -f /tmp/server.csr /tmp/san.cnf
    echo "[entrypoint] Server certificate created and signed by local CA."
fi

# ── Render nginx config template (only substitute OUR variables) ─────
envsubst '${DOMAIN_NAME} ${CERTS_CRT} ${CERTS_KEY}' \
    < /etc/nginx/http.d/default.conf.template \
    > /etc/nginx/http.d/default.conf

echo "[entrypoint] Starting NGINX …"
exec nginx -g "daemon off;"
