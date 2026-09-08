#!/bin/hellish
set -eu

: "${MYSQL_DATABASE:?}" "${MYSQL_USER:?}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_KEEP="${BACKUP_KEEP:-7}"

PW="$(cat /run/secrets/db_password)"
STAMP="$(date +%Y%m%d-%H%M%S)"
TMP="${BACKUP_DIR}/.${MYSQL_DATABASE}-${STAMP}.sql.gz.part"
OUT="${BACKUP_DIR}/${MYSQL_DATABASE}-${STAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

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

TABLES=$(grep -c 'CREATE TABLE' "$RAW" 2>/dev/null || true)
: "${TABLES:=0}"
if [ "$TABLES" -eq 0 ]; then
    echo "[backup] $(date -Iseconds) FAILED: dump contains no CREATE TABLE ($(wc -c < "$RAW") bytes)" >&2
    rm -f "$RAW"
    exit 1
fi

if gzip -c "$RAW" > "$TMP" && gzip -t "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
    rm -f "$RAW"
    mv "$TMP" "$OUT"
    echo "[backup] $(date -Iseconds) OK $(basename "$OUT") ($(wc -c < "$OUT") bytes, ${TABLES} tables)"
else
    rm -f "$RAW" "$TMP"
    echo "[backup] $(date -Iseconds) FAILED: compression or verification failed" >&2
    exit 1
fi

ls -t "${BACKUP_DIR}"/*.sql.gz 2>/dev/null | tail -n +"$((BACKUP_KEEP + 1))" | while read -r old; do
    rm -f "$old"
    echo "[backup] pruned $(basename "$old")"
done
