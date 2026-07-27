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

MARKER=/var/lib/mysql/.inception_init_done

# ── Create system tables on a fresh volume ───────────────────────────
if [ ! -d /var/lib/mysql/mysql ]; then
    echo "[entrypoint] Initialising MariaDB data directory ..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db \
        > /dev/null 2>&1
fi

# ── One-time bootstrap: root password, application DB and user ──────
# Runs in mariadbd --bootstrap mode: the SQL is applied directly, with
# no temporary server, no client and no authentication — so an
# interrupted first boot retries cleanly whatever state it died in.
# All statements are idempotent; the marker is written only after full
# success.
if [ ! -f "$MARKER" ]; then
    echo "[entrypoint] Bootstrapping database and users ..."
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
    touch "$MARKER"
    echo "[entrypoint] Bootstrap complete."
fi

# ── Start MariaDB as PID 1 ───────────────────────────────────────────
echo "[entrypoint] Starting MariaDB ..."
exec mariadbd --user=mysql
