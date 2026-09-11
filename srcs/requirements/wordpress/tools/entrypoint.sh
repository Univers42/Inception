#!/bin/hellish
# shellcheck shell=sh
set -eu

: "${DOMAIN_NAME:?}" "${MYSQL_DATABASE:?}" "${MYSQL_USER:?}" "${WP_TITLE:?}"
WP_REDIS_HOST="${WP_REDIS_HOST:-redis}"
php_escape_pw() { printf %s "$1" | sed 's/\\/\\\\/g; s/'\''/\\'\''/g'; }
WP_REDIS_PORT="${WP_REDIS_PORT:-6379}"
: "${WP_ADMIN_USER:?}" "${WP_ADMIN_EMAIL:?}" "${WP_USER:?}" "${WP_USER_EMAIL:?}"

case "$(printf %s "$WP_ADMIN_USER" | tr '[:upper:]' '[:lower:]')" in
    *admin*)
        echo "[entrypoint] ERROR: WP_ADMIN_USER '$WP_ADMIN_USER' must not contain 'admin'" >&2
        exit 1 ;;
esac

WP_ADMIN_PASSWORD="$(sed -n 1p /run/secrets/credentials)"
WP_USER_PASSWORD="$(sed -n 2p /run/secrets/credentials)"
MYSQL_PASSWORD="$(cat /run/secrets/db_password)"
[ -n "$WP_ADMIN_PASSWORD" ] && [ -n "$WP_USER_PASSWORD" ] || {
    echo "[entrypoint] ERROR: secrets/credentials.txt needs two non-empty lines" >&2
    exit 1
}

echo "[entrypoint] Waiting for MariaDB ..."
i=0
until WPDB_PW="$MYSQL_PASSWORD" php -r '
        mysqli_report(MYSQLI_REPORT_OFF);
        exit(@mysqli_connect("mariadb", $argv[1], getenv("WPDB_PW"), $argv[2]) ? 0 : 1);
    ' "$MYSQL_USER" "$MYSQL_DATABASE" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 60 ]; then
        echo "[entrypoint] ERROR: MariaDB unreachable after 60s" >&2
        exit 1
    fi
    sleep 1
done
echo "[entrypoint] MariaDB is ready."

if [ ! -f /var/www/html/wp-config.php ]; then
    if [ ! -f /var/www/html/wp-includes/version.php ]; then
        echo "[entrypoint] Deploying WordPress core from image ..."
        cp -a /usr/src/wordpress/. /var/www/html/
    fi

    echo "[entrypoint] Writing wp-config.php ..."
    php_escape() { printf %s "$1" | sed 's/\\/\\\\/g; s/'\''/\\'\''/g'; }
    SALTS="$(php -r 'foreach (["AUTH_KEY","SECURE_AUTH_KEY","LOGGED_IN_KEY","NONCE_KEY","AUTH_SALT","SECURE_AUTH_SALT","LOGGED_IN_SALT","NONCE_SALT"] as $k) printf("define( %c%s%c, %c%s%c );\n", 39, $k, 39, 39, bin2hex(random_bytes(32)), 39);')"
    cat > /var/www/html/wp-config.php <<EOF
<?php
define( 'DB_NAME', '$(php_escape "$MYSQL_DATABASE")' );
define( 'DB_USER', '$(php_escape "$MYSQL_USER")' );
define( 'DB_PASSWORD', '$(php_escape "$MYSQL_PASSWORD")' );
define( 'DB_HOST', 'mariadb:3306' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );
${SALTS}
\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );

// Serve the same install correctly under any of the TLS certificate's SANs
// (the subject-mandated domain, plus localhost/127.0.0.1 for VM port-forwarded
// access from an unprivileged host with no /etc/hosts write access) instead of
// hard-redirecting every other Host to the canonical domain. Anything outside
// this whitelist still falls back to the canonical domain — never trusts an
// arbitrary client-supplied Host header.
\$__allowed_hosts = array( '${DOMAIN_NAME}', 'localhost', '127.0.0.1' );
\$__host = isset( \$_SERVER['HTTP_HOST'] ) ? \$_SERVER['HTTP_HOST'] : '${DOMAIN_NAME}';
\$__host_only = preg_replace( '/:[0-9]+\$/', '', \$__host );
if ( ! in_array( \$__host_only, \$__allowed_hosts, true ) ) {
    \$__host = '${DOMAIN_NAME}';
}
define( 'WP_HOME', 'https://' . \$__host );
define( 'WP_SITEURL', 'https://' . \$__host );

// Object cache (bonus). WordPress rebuilds the same options, posts and terms
// from MariaDB on every request; with these set, the redis-cache drop-in keeps
// them in Redis instead. The key salt is the domain, so two installs sharing a
// Redis instance cannot read each other's entries.
define( 'WP_REDIS_HOST', '${WP_REDIS_HOST}' );
define( 'WP_REDIS_PORT', ${WP_REDIS_PORT} );
define( 'WP_REDIS_TIMEOUT', 1 );
define( 'WP_REDIS_READ_TIMEOUT', 1 );
define( 'WP_CACHE_KEY_SALT', '${DOMAIN_NAME}' );
define( 'WP_CACHE', true );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
EOF
    chown nobody:nobody /var/www/html/wp-config.php
    chmod 640 /var/www/html/wp-config.php

    echo "[entrypoint] Installing WordPress ..."
    wp core install --allow-root \
        --url="https://${DOMAIN_NAME}" \
        --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email \
        --path=/var/www/html

    echo "[entrypoint] Creating editor user ..."
    wp user create --allow-root \
        "$WP_USER" "$WP_USER_EMAIL" \
        --role=editor \
        --user_pass="$WP_USER_PASSWORD" \
        --path=/var/www/html

    find /var/www/html -user root -exec chown nobody:nobody {} + 2>/dev/null || true
    echo "[entrypoint] WordPress setup complete."
fi

if [ -f /var/www/html/wp-config.php ]; then
    ESC_PW="$(php_escape_pw "$MYSQL_PASSWORD")"
    if ! grep -qF "define( 'DB_PASSWORD', '${ESC_PW}' );" /var/www/html/wp-config.php; then
        echo "[entrypoint] wp-config.php holds a stale DB_PASSWORD — syncing it with the mounted secret ..."
        TMP_PW=$(mktemp)
        if awk -v pw="$ESC_PW" '
                /^define\( *.DB_PASSWORD./ {
                    printf "define( %cDB_PASSWORD%c, %c%s%c );\n", 39,39,39,pw,39
                    next
                }
                { print }
            ' /var/www/html/wp-config.php > "$TMP_PW" && [ -s "$TMP_PW" ]; then
            cat "$TMP_PW" > /var/www/html/wp-config.php
        else
            echo "[entrypoint] WARN: could not update DB_PASSWORD in wp-config.php" >&2
        fi
        rm -f "$TMP_PW"
    fi
fi

if wp core is-installed --allow-root --path=/var/www/html 2>/dev/null; then
    sync_wp_password() {
        [ -n "$1" ] && [ -n "$2" ] || return 0
        wp eval --allow-root --path=/var/www/html \
            "exit( is_wp_error( wp_authenticate( \$argv[0], \$argv[1] ) ) ? 1 : 0 );" \
            "$1" "$2" > /dev/null 2>&1 && return 0
        echo "[entrypoint] '$1' password does not match the secret — resetting it ..."
        wp user update "$1" --user_pass="$2" --skip-email \
            --allow-root --path=/var/www/html > /dev/null 2>&1 \
            || echo "[entrypoint] WARN: could not reset the password for '$1'" >&2
    }
    sync_wp_password "$WP_ADMIN_USER" "$WP_ADMIN_PASSWORD"
    sync_wp_password "$WP_USER"       "$WP_USER_PASSWORD"
fi

if [ -f /var/www/html/wp-config.php ] \
   && ! grep -q 'WP_REDIS_HOST' /var/www/html/wp-config.php; then
    echo "[entrypoint] Adding Redis cache settings to the existing wp-config.php ..."
    TMP_CFG=$(mktemp)
    if awk -v host="$WP_REDIS_HOST" -v port="$WP_REDIS_PORT" -v salt="$DOMAIN_NAME" '
            !added && index($0, "ABSPATH") && index($0, "defined") {
                printf "define( %cWP_REDIS_HOST%c, %c%s%c );\n", 39,39,39,host,39
                printf "define( %cWP_REDIS_PORT%c, %s );\n", 39,39,port
                printf "define( %cWP_REDIS_TIMEOUT%c, 1 );\n", 39,39
                printf "define( %cWP_REDIS_READ_TIMEOUT%c, 1 );\n", 39,39
                printf "define( %cWP_CACHE_KEY_SALT%c, %c%s%c );\n", 39,39,39,salt,39
                printf "define( %cWP_CACHE%c, true );\n\n", 39,39
                added = 1
            }
            { print }
        ' /var/www/html/wp-config.php > "$TMP_CFG" && [ -s "$TMP_CFG" ]; then
        cat "$TMP_CFG" > /var/www/html/wp-config.php
    else
        echo "[entrypoint] WARN: could not patch wp-config.php for Redis" >&2
    fi
    rm -f "$TMP_CFG"
fi

hellish /usr/src/inception-site/install.sh \
    || echo "[entrypoint] WARN: site provisioning failed (service boots anyway)" >&2

enable_redis_cache() {
    if ! wp plugin is-active redis-cache --allow-root --path=/var/www/html 2>/dev/null; then
        wp plugin install redis-cache --force --activate \
            --allow-root --path=/var/www/html || return 1
    fi
    [ -s /var/www/html/wp-content/object-cache.php ] \
        || wp redis enable --allow-root --path=/var/www/html || return 1
}
if enable_redis_cache; then
    echo "[entrypoint] Redis object cache enabled."
else
    echo "[entrypoint] WARN: could not enable the Redis object cache (site boots anyway)" >&2
fi

echo "[entrypoint] Starting php-fpm ..."
exec php-fpm84 -F
