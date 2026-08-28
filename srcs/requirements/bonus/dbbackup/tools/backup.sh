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
#
# The dump goes to a plain file FIRST, deliberately not straight into a pipe.
# `mariadb-dump ... | gzip > out` returns the exit status of gzip, the last
# command in the pipeline — so a dump that failed with "Access denied" still
# looked like success, and gzip of nothing is a perfectly valid 20-byte
# archive that passes both `gzip -t` and a non-empty test. That is exactly how
# an empty backup gets kept and is discovered to be worthless on the day it is
# needed; it happened here, and B05 in the compliance suite caught it.
RAW="${BACKUP_DIR}/.${MYSQL_DATABASE}-${STAMP}.sql.part"
if ! MYSQL_PWD="$PW" mariadb-dump \
        --host=mariadb \
        --user="$MYSQL_USER" \
        --single-transaction \
        --quick \
        --skip-lock-tables \
        "$MYSQL_DATABASE" > "$RAW" 2>/tmp/dump.err; then
    echo "[backup] $(date -Iseconds) FAILED: $(tail -1 /tmp/dump.err 2>/dev/null)" >&2
    rm -f "$RAW"
    exit 1
fi

# A dump with no schema in it is not a backup, whatever its exit status said.
TABLES=$(grep -c 'CREATE TABLE' "$RAW" 2>/dev/null || echo 0)
if [ "$TABLES" -eq 0 ]; then
    echo "[backup] $(date -Iseconds) FAILED: dump contains no CREATE TABLE ($(wc -c < "$RAW") bytes)" >&2
    rm -f "$RAW"
    exit 1
fi

# Compress to a .part file and rename only on success, so an interrupted run
# can never leave a truncated file that looks like a usable backup.
if gzip -c "$RAW" > "$TMP" && gzip -t "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
    rm -f "$RAW"
    mv "$TMP" "$OUT"
    # Table count comes from the RAW dump, counted before compression — grepping
    # the .gz would search binary and always report 0.
    echo "[backup] $(date -Iseconds) OK $(basename "$OUT") ($(wc -c < "$OUT") bytes, ${TABLES} tables)"
else
    rm -f "$RAW" "$TMP"
    echo "[backup] $(date -Iseconds) FAILED: compression or verification failed" >&2
    exit 1
fi

# Retention: keep the newest $BACKUP_KEEP, delete the rest.
ls -t "${BACKUP_DIR}"/*.sql.gz 2>/dev/null | tail -n +"$((BACKUP_KEEP + 1))" | while read -r old; do
    rm -f "$old"
    echo "[backup] pruned $(basename "$old")"
done
