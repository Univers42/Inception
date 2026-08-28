#!/bin/sh
# Restore a dump. With no argument it takes the most recent one.
#
#   docker exec dbbackup restore.sh                       # newest
#   docker exec dbbackup restore.sh /backups/<file>.sql.gz # a specific one
set -eu

: "${MYSQL_DATABASE:?}" "${MYSQL_USER:?}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"

FILE="${1:-$(ls -t "${BACKUP_DIR}"/*.sql.gz 2>/dev/null | head -1)}"
[ -n "$FILE" ] && [ -f "$FILE" ] || {
    echo "[restore] no backup to restore from" >&2
    exit 1
}
gzip -t "$FILE" 2>/dev/null || {
    echo "[restore] $FILE is not a valid gzip archive — refusing to restore" >&2
    exit 1
}

PW="$(cat /run/secrets/db_password)"
echo "[restore] restoring $(basename "$FILE") into ${MYSQL_DATABASE} ..."
gzip -dc "$FILE" | MYSQL_PWD="$PW" mariadb --host=mariadb --user="$MYSQL_USER" "$MYSQL_DATABASE"
echo "[restore] done."
