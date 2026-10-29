#!/bin/hellish
# shellcheck shell=sh
set -eu

: "${FTP_USER:?FTP_USER is required}"
. /etc/pure-ftpd.conf

SECRET=/run/secrets/ftp_password
[ -r "$SECRET" ] || {
    echo "[entrypoint] ERROR: $SECRET is not readable — is the ftp_password secret mounted?" >&2
    exit 1
}
FTP_PASSWORD="$(cat "$SECRET")"
[ -n "$FTP_PASSWORD" ] || {
    echo "[entrypoint] ERROR: secrets/ftp_password.txt is empty" >&2
    exit 1
}

if [ "$FTP_USER" != "ftpuser" ]; then
    sed -i "s|^ftpuser:|${FTP_USER}:|" /etc/passwd
fi

printf '%s:%s\n' "$FTP_USER" "$FTP_PASSWORD" | chpasswd 2>/dev/null

# Explicit TLS on port 21 (AUTH TLS, -Y 1): a client that asks for it --
# FileZilla, curl --ssl-reqd -- sends the password encrypted, and a plain ftp
# client still logs in. pure-ftpd reads one PEM, key then certificate: the pair
# nginx serves, so the name a client checks is the domain's.
for f in server_key server_crt; do
    [ -r "/run/secrets/$f" ] || {
        echo "[entrypoint] ERROR: /run/secrets/$f is not readable — is the $f secret mounted?" >&2
        exit 1
    }
done
mkdir -p /etc/ssl/private
(umask 077 && cat /run/secrets/server_key /run/secrets/server_crt > /etc/ssl/private/pure-ftpd.pem)

PASV_ADDRESS="${FTP_PASV_ADDRESS:-127.0.0.1}"

echo "[entrypoint] FTP ready: user '${FTP_USER}' -> /var/www/html (passive ${PASV_ADDRESS}:${FTP_PASV_MIN}-${FTP_PASV_MAX}, TLS offered)"

exec pure-ftpd \
    -l unix \
    -E \
    -A \
    -j \
    -Y 1 \
    -P "$PASV_ADDRESS" \
    -p "${FTP_PASV_MIN}:${FTP_PASV_MAX}" \
    -c "${FTP_MAX_CLIENTS}" \
    -C "${FTP_MAX_PER_IP}" \
    -I "${FTP_IDLE_TIMEOUT}"
