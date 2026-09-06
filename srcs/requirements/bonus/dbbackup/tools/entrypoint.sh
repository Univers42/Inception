#!/bin/sh
set -eu

: "${MYSQL_DATABASE:?}" "${MYSQL_USER:?}"
BACKUP_CRON="${BACKUP_CRON:-0 */6 * * *}"
BACKUP_KEEP="${BACKUP_KEEP:-7}"
export MYSQL_DATABASE MYSQL_USER BACKUP_KEEP
BACKUP_DIR="${BACKUP_DIR:-/backups}"
export BACKUP_DIR

# Bounded wait for the WordPress schema, not merely for the port: the first
# backup below is only worth taking once there are tables to dump. compose
# already orders this service after a healthy wordpress; this is the same
# condition checked where it matters, and it covers a restart of this
# container alone.
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

# One backup now. A scheduled job that has never run is a promise, not a
# backup — this makes the service demonstrably working from the moment it
# starts, and gives the healthcheck something to verify.
echo "[entrypoint] Taking an initial backup ..."
backup.sh || echo "[entrypoint] WARN: initial backup failed; the schedule still applies" >&2

# The environment is not inherited by cron jobs, so it is written into the
# crontab line itself rather than assumed.
mkdir -p /etc/crontabs
cat > /etc/crontabs/root <<CRONEOF
${BACKUP_CRON} MYSQL_DATABASE='${MYSQL_DATABASE}' MYSQL_USER='${MYSQL_USER}' BACKUP_KEEP='${BACKUP_KEEP}' BACKUP_DIR='${BACKUP_DIR}' /usr/local/bin/backup.sh
CRONEOF

echo "[entrypoint] Schedule: ${BACKUP_CRON} (keeping ${BACKUP_KEEP} backups in ${BACKUP_DIR})"

# crond in the foreground, logging to stdout. This is a real daemon, not a
# keep-alive loop: exec makes it PID 1.
exec crond -f -l 8 -L /dev/stdout
