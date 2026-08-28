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

# The account is baked into /etc/passwd at build time (uid 65534, shared with
# nobody). Rename it if FTP_USER was customised, so the login name stays
# configurable without giving up the uid that makes permissions work.
if [ "$FTP_USER" != "ftpuser" ]; then
    sed -i "s|^ftpuser:|${FTP_USER}:|" /etc/passwd
fi

# Password is applied at runtime from the Docker secret, never baked into a
# layer: anything written during build survives in the image history.
printf '%s:%s\n' "$FTP_USER" "$FTP_PASSWORD" | chpasswd 2>/dev/null

# The address advertised for passive data connections. Both routes to this
# server arrive over loopback — inside the VM the client already is on
# localhost, and from the physical host VirtualBox NAT forwards the host's own
# loopback — so 127.0.0.1 is correct for both.
PASV_ADDRESS="${FTP_PASV_ADDRESS:-127.0.0.1}"

echo "[entrypoint] FTP ready: user '${FTP_USER}' -> /var/www/html (passive ${PASV_ADDRESS}:${FTP_PASV_MIN}-${FTP_PASV_MAX})"

# Flags, in order:
#   -l unix   authenticate against /etc/passwd
#   -E        no anonymous login: this writes into the live website
#   -A        chroot every user to their home, so a client cannot walk out of
#             /var/www/html into the rest of the container
#   -j        create the home directory if it is missing
#   -P/-p     passive address and port range (see conf/pure-ftpd.conf)
#   -c/-C     concurrency limits
#   -I        idle timeout
#
# No -B: pure-ftpd stays in the foreground by default, so exec makes it PID 1
# and Docker's stop signal and restart policy act on the daemon itself.
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
