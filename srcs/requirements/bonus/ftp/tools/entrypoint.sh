#!/bin/sh
set -eu

: "${FTP_USER:?FTP_USER is required}"

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
# configurable without giving up the uid trick that makes permissions work.
if [ "$FTP_USER" != "ftpuser" ]; then
    sed -i "s|^ftpuser:|${FTP_USER}:|" /etc/passwd
fi

# Password is set at runtime from the Docker secret, never baked into a layer:
# anything written during build survives in the image history.
printf '%s:%s\n' "$FTP_USER" "$FTP_PASSWORD" | chpasswd 2>/dev/null

# The address vsftpd advertises for passive data connections. Both routes to
# this server arrive over loopback — inside the VM the client already is on
# localhost, and from the physical host VirtualBox NAT forwards the host's own
# loopback — so 127.0.0.1 is correct for both.
PASV_ADDRESS="${FTP_PASV_ADDRESS:-127.0.0.1}"
if grep -q '^pasv_address=' /etc/vsftpd/vsftpd.conf; then
    sed -i "s|^pasv_address=.*|pasv_address=${PASV_ADDRESS}|" /etc/vsftpd/vsftpd.conf
else
    echo "pasv_address=${PASV_ADDRESS}" >> /etc/vsftpd/vsftpd.conf
fi

echo "[entrypoint] FTP ready: user '${FTP_USER}' -> /var/www/html (passive ${PASV_ADDRESS}:21000-21010)"

# exec: vsftpd is PID 1 and runs in the foreground (background=NO is its
# default), so no supervisor and nothing to keep the container alive artificially.
exec vsftpd /etc/vsftpd/vsftpd.conf
