#!/bin/sh
set -eu

: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"

# ── Read Docker secrets ──────────────────────────────────────────────
MYSQL_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"
MYSQL_PASSWORD="$(cat /run/secrets/db_password)"
[ -n "$MYSQL_ROOT_PASSWORD" ] && [ -n "$MYSQL_PASSWORD" ] || {
    echo "[entrypoint] ERROR: db_root_password / db_password secrets are empty" >&2
    exit 1
}

# Escape single quotes so passwords are safe inside SQL string literals
sql_escape() { printf %s "$1" | sed "s/'/''/g"; }
ROOT_PW_SQL="$(sql_escape "$MYSQL_ROOT_PASSWORD")"
USER_PW_SQL="$(sql_escape "$MYSQL_PASSWORD")"

# ── Create system tables on a fresh volume ───────────────────────────
if [ ! -d /var/lib/mysql/mysql ]; then
    echo "[entrypoint] Initialising MariaDB data directory ..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db \
        > /dev/null 2>&1
fi

# ── Reconcile the root password, application DB and user on EVERY boot ──
# Runs in mariadbd --bootstrap mode: the SQL is applied directly, with
# no temporary server, no client and no authentication — so an
# interrupted boot retries cleanly from whatever state it died in.
#
# This deliberately runs every time rather than once behind a marker file.
# The marker used to live in /var/lib/mysql, i.e. inside the data
# directory — and that directory is a bind mount onto the host, so it
# OUTLIVES `docker volume rm`. The evaluation sheet's cleanup removes
# containers, images and volumes but cannot touch the host path, so:
#
#   cleanup  ->  fresh clone  ->  secrets/ is empty (correctly gitignored)
#            ->  make setup generates NEW random passwords
#            ->  data directory still holds the OLD ones
#            ->  marker present, bootstrap skipped, credentials never updated
#            ->  ERROR 1045 Access denied, wordpress restart-loops,
#                nginx never starts, and the evaluation ends there.
#
# Every statement below is idempotent, so re-running costs about a second
# and makes the database agree with whatever secrets are current.
echo "[entrypoint] Reconciling database and users with the current secrets ..."
mariadbd --user=mysql --bootstrap <<EOSQL
USE mysql;
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PW_SQL}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${USER_PW_SQL}';
ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${USER_PW_SQL}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL
echo "[entrypoint] Database and users are in sync with the mounted secrets."

# ── Start MariaDB as PID 1 ───────────────────────────────────────────
echo "[entrypoint] Starting MariaDB ..."
exec mariadbd --user=mysql
