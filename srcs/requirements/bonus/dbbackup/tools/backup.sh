#!/bin/sh
# One backup run: dump, compress, verify, prune. Called by cron and once at
# startup so there is always evidence the service works.
set -eu

: "${MYSQL_DATABASE:?}" "${MYSQL_USER:?}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_KEEP="${BACKUP_KEEP:-7}"

PW="$(cat /run/secrets/db_password)"
STAMP="$(date +%Y%m%d-%H%M%S)"
TMP="${BACKUP_DIR}/.${MYSQL_DATABASE}-${STAMP}.sql.gz.part"
OUT="${BACKUP_DIR}/${MYSQL_DATABASE}-${STAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

# --single-transaction takes the dump from one consistent snapshot without
# locking the tables, so the site keeps serving while this runs.
# Written to a .part file and renamed only on success: an interrupted run can
# never leave a truncated file that looks like a usable backup.
if MYSQL_PWD="$PW" mariadb-dump \
        --host=mariadb \
        --user="$MYSQL_USER" \
        --single-transaction \
        --quick \
        --skip-lock-tables \
        "$MYSQL_DATABASE" 2>/tmp/dump.err | gzip -c > "$TMP"; then
    if gzip -t "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
        mv "$TMP" "$OUT"
        echo "[backup] $(date -Iseconds) OK $(basename "$OUT") ($(wc -c < "$OUT") bytes)"
    else
        rm -f "$TMP"
        echo "[backup] $(date -Iseconds) FAILED: dump was empty or corrupt" >&2
        exit 1
    fi
else
    rm -f "$TMP"
    echo "[backup] $(date -Iseconds) FAILED: $(tail -1 /tmp/dump.err 2>/dev/null)" >&2
    exit 1
fi

# Retention: keep the newest $BACKUP_KEEP, delete the rest.
ls -t "${BACKUP_DIR}"/*.sql.gz 2>/dev/null | tail -n +"$((BACKUP_KEEP + 1))" | while read -r old; do
    rm -f "$old"
    echo "[backup] pruned $(basename "$old")"
done
