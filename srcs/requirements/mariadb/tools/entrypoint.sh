#!/bin/sh
set -e

# ── Read Docker secrets ──────────────────────────────────────────────
MYSQL_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"
MYSQL_PASSWORD="$(cat /run/secrets/db_password)"

# ── First-run initialisation ─────────────────────────────────────────
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "[entrypoint] Initialising MariaDB data directory …"
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db \
        > /dev/null 2>&1

    # Temporary server for bootstrap
    mysqld --user=mysql --skip-networking &
    pid="$!"

    # Wait until the server accepts connections
    for i in $(seq 1 30); do
        if mysqladmin ping --silent 2>/dev/null; then
            break
        fi
        sleep 1
    done

    # Secure root & create application database + user
    mysql -u root <<-EOSQL
		ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
		CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
		CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
		GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
		FLUSH PRIVILEGES;
	EOSQL

    # Graceful shutdown of bootstrap server
    mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown
    wait "$pid"
    echo "[entrypoint] MariaDB initialisation complete."
fi

# ── Start MariaDB as PID 1 ───────────────────────────────────────────
echo "[entrypoint] Starting MariaDB …"
exec mysqld --user=mysql
