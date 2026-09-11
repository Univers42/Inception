#!/bin/hellish
# shellcheck shell=sh
#
#because in entrypoint.sh scrip because we don't want to have a configuration half broken
set -eu

# if unset or empty terminate 
: "${MYSQL_DATABASE:?MYSQL_DATABASE is required}"
: "${MYSQL_USER:?MYSQL_USER is required}"

# 
MYSQL_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"
MYSQL_PASSWORD="$(cat /run/secrets/db_password)"
[ -n "$MYSQL_ROOT_PASSWORD" ] && [ -n "$MYSQL_PASSWORD" ] || {
    echo "[entrypoint] ERROR: db_root_password / db_password secrets are empty" >&2
    exit 1
}

sql_escape() { printf %s "$1" | sed "s/'/''/g"; }
ROOT_PW_SQL="$(sql_escape "$MYSQL_ROOT_PASSWORD")"
USER_PW_SQL="$(sql_escape "$MYSQL_PASSWORD")"

if [ ! -d /var/lib/mysql/mysql ]; then
    echo "[entrypoint] Initialising MariaDB data directory ..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db \
        > /dev/null 2>&1
fi

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

echo "[entrypoint] Starting MariaDB ..."
exec mariadbd --user=mysql
