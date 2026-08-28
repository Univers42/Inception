#!/bin/sh
set -eu

: "${DOMAIN_NAME:?}" "${MYSQL_DATABASE:?}" "${MYSQL_USER:?}" "${WP_TITLE:?}"
WP_REDIS_HOST="${WP_REDIS_HOST:-redis}"
WP_REDIS_PORT="${WP_REDIS_PORT:-6379}"
: "${WP_ADMIN_USER:?}" "${WP_ADMIN_EMAIL:?}" "${WP_USER:?}" "${WP_USER_EMAIL:?}"

# ── Subject rule: admin username must not contain admin/Admin/... ────
case "$(printf %s "$WP_ADMIN_USER" | tr '[:upper:]' '[:lower:]')" in
    *admin*)
        echo "[entrypoint] ERROR: WP_ADMIN_USER '$WP_ADMIN_USER' must not contain 'admin'" >&2
        exit 1 ;;
esac

# ── Read Docker secrets (line 1 = admin pw, line 2 = editor pw) ─────
WP_ADMIN_PASSWORD="$(sed -n 1p /run/secrets/credentials)"
WP_USER_PASSWORD="$(sed -n 2p /run/secrets/credentials)"
MYSQL_PASSWORD="$(cat /run/secrets/db_password)"
[ -n "$WP_ADMIN_PASSWORD" ] && [ -n "$WP_USER_PASSWORD" ] || {
    echo "[entrypoint] ERROR: secrets/credentials.txt needs two non-empty lines" >&2
    exit 1
}

# ── Bounded wait until MariaDB accepts the application user ──────────
# php-mysqli does the probing; no database client package required.
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

# ── One-time WordPress installation ──────────────────────────────────
if [ ! -f /var/www/html/wp-config.php ]; then
    if [ ! -f /var/www/html/wp-includes/version.php ]; then
        echo "[entrypoint] Deploying WordPress core from image ..."
        cp -a /usr/src/wordpress/. /var/www/html/
    fi

    echo "[entrypoint] Writing wp-config.php ..."
    # Heredoc instead of `wp config create` — saves a full PHP/WP-CLI boot.
    # Salts are generated locally (hex only, so no quoting hazards);
    # passwords are escaped for PHP single-quoted strings.
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

    # cp -a preserved nobody ownership from the image; only pick up any
    # stragglers created as root during the install (full-tree chown -R
    # over ~2600 files costs ~1s and is unnecessary)
    find /var/www/html -user root -exec chown nobody:nobody {} + 2>/dev/null || true
    echo "[entrypoint] WordPress setup complete."
fi

# ── Object cache (bonus): wire an EXISTING install up to Redis ───────
# The wp-config.php heredoc above only runs on a first install, and the site
# volume outlives image rebuilds — so an install created before Redis existed
# would never gain these constants. Append them once, idempotently, before the
# ABSPATH guard: anything after that line is the bootstrap and is read too late.
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

# ── Deploy the documentation site (theme, plugin, seeded content) ────
# Idempotent and deliberately NON-FATAL: site provisioning must never
# be able to break the service boot path.
sh /usr/src/inception-site/install.sh \
    || echo "[entrypoint] WARN: site provisioning failed (service boots anyway)" >&2

# ── Object cache (bonus): plugin + drop-in ───────────────────────────
# NON-FATAL, like the site provisioning above: a cache is an optimisation, and a
# Redis problem must never be able to stop WordPress from booting.
enable_redis_cache() {
    wp plugin is-installed redis-cache --allow-root --path=/var/www/html 2>/dev/null \
        || wp plugin install redis-cache --allow-root --path=/var/www/html || return 1
    wp plugin is-active redis-cache --allow-root --path=/var/www/html 2>/dev/null \
        || wp plugin activate redis-cache --allow-root --path=/var/www/html || return 1
    # `wp redis enable` writes wp-content/object-cache.php — the drop-in that
    # actually routes WordPress's cache calls to Redis. Without it the plugin is
    # installed and the cache is still doing nothing.
    [ -f /var/www/html/wp-content/object-cache.php ] \
        || wp redis enable --allow-root --path=/var/www/html || return 1
}
if enable_redis_cache; then
    echo "[entrypoint] Redis object cache enabled."
else
    echo "[entrypoint] WARN: could not enable the Redis object cache (site boots anyway)" >&2
fi

# ── Start php-fpm as PID 1 ───────────────────────────────────────────
echo "[entrypoint] Starting php-fpm ..."
exec php-fpm84 -F
