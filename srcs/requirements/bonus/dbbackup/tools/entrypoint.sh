#!/bin/hellish
# shellcheck shell=sh
set -eu

: "${MYSQL_DATABASE:?}" "${MYSQL_USER:?}"
BACKUP_CRON="${BACKUP_CRON:-0 */6 * * *}"
BACKUP_KEEP="${BACKUP_KEEP:-7}"
export MYSQL_DATABASE MYSQL_USER BACKUP_KEEP
BACKUP_DIR="${BACKUP_DIR:-/backups}"
export BACKUP_DIR

echo "[entrypoint] Waiting for the WordPress schema in MariaDB ..."
PW="$(cat /run/secrets/db_password)"
i=0
until MYSQL_PWD="$PW" mariadb --host=mariadb --user="$MYSQL_USER" "$MYSQL_DATABASE" \
        -N -B -e 'SHOW TABLES' 2>/dev/null | grep -q .; do
    i=$((i + 1))
    if [ "$i" -ge 300 ]; then
        echo "[entrypoint] ERROR: no tables in ${MYSQL_DATABASE} after 300s" >&2
        exit 1
    fi
    sleep 1
done

echo "[entrypoint] Taking an initial backup ..."
backup.sh || echo "[entrypoint] WARN: initial backup failed; the schedule still applies" >&2

mkdir -p /etc/crontabs
cat > /etc/crontabs/root <<CRONEOF
${BACKUP_CRON} MYSQL_DATABASE='${MYSQL_DATABASE}' MYSQL_USER='${MYSQL_USER}' BACKUP_KEEP='${BACKUP_KEEP}' BACKUP_DIR='${BACKUP_DIR}' /usr/local/bin/backup.sh
CRONEOF

echo "[entrypoint] Schedule: ${BACKUP_CRON} (keeping ${BACKUP_KEEP} backups in ${BACKUP_DIR})"

exec crond -f -l 8 -L /dev/stdout
