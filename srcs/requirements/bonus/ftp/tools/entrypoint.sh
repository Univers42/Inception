#!/bin/sh
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

PASV_ADDRESS="${FTP_PASV_ADDRESS:-127.0.0.1}"

echo "[entrypoint] FTP ready: user '${FTP_USER}' -> /var/www/html (passive ${PASV_ADDRESS}:${FTP_PASV_MIN}-${FTP_PASV_MAX})"

exec pure-ftpd \
    -l unix \
    -E \
    -A \
    -j \
    -P "$PASV_ADDRESS" \
    -p "${FTP_PASV_MIN}:${FTP_PASV_MAX}" \
    -c "${FTP_MAX_CLIENTS}" \
    -C "${FTP_MAX_PER_IP}" \
    -I "${FTP_IDLE_TIMEOUT}"
