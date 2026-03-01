#!/bin/sh
set -e

# ── Read Docker secrets ──────────────────────────────────────────────
WP_ADMIN_PASSWORD="$(head -n 1 /run/secrets/credentials)"
WP_USER_PASSWORD="$(tail  -n 1 /run/secrets/credentials)"
MYSQL_PASSWORD="$(cat /run/secrets/db_password)"

# ── Prepare OPcache file cache directory ─────────────────────────────
mkdir -p /tmp/opcache && chown nobody:nobody /tmp/opcache

# ── Wait for MariaDB ─────────────────────────────────────────────────
echo "[entrypoint] Waiting for MariaDB …"
until mysqladmin ping -h mariadb -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" --silent 2>/dev/null; do
    sleep 1
done
echo "[entrypoint] MariaDB is ready."

# ── Install & configure WordPress on first run ───────────────────────
if [ ! -f /var/www/html/wp-config.php ]; then
    # Core files are pre-downloaded in the image; download default themes/plugins
    if [ ! -f /var/www/html/wp-includes/version.php ]; then
        echo "[entrypoint] Downloading WordPress core …"
        wp core download --allow-root --path=/var/www/html
    else
        echo "[entrypoint] WordPress core already cached in image."
        # Download default content (themes/plugins) that was skipped at build
        wp core download --allow-root --path=/var/www/html --skip-content 2>/dev/null || true
    fi

    echo "[entrypoint] Creating wp-config.php …"
    wp config create --allow-root \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${MYSQL_PASSWORD}" \
        --dbhost=mariadb:3306 \
        --path=/var/www/html

    # Inject extra performance constants into wp-config.php
    wp config set --allow-root --type=constant WP_CACHE true --raw --path=/var/www/html
    wp config set --allow-root --type=constant DISABLE_WP_CRON false --raw --path=/var/www/html
    wp config set --allow-root --type=constant WP_POST_REVISIONS 3 --raw --path=/var/www/html
    wp config set --allow-root --type=constant EMPTY_TRASH_DAYS 7 --raw --path=/var/www/html

    echo "[entrypoint] Installing WordPress …"
    wp core install --allow-root \
        --url="https://${DOMAIN_NAME}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --path=/var/www/html

    echo "[entrypoint] Creating editor user …"
    wp user create --allow-root \
        "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=editor \
        --user_pass="${WP_USER_PASSWORD}" \
        --path=/var/www/html

    chown -R nobody:nobody /var/www/html
    echo "[entrypoint] WordPress setup complete."
fi

# ── Start php-fpm as PID 1 ───────────────────────────────────────────
echo "[entrypoint] Starting php-fpm …"
exec php-fpm83 -F
