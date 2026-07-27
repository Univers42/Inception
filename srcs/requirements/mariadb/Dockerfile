# Penultimate stable Alpine (subject requirement) — latest stable is 3.24
FROM alpine:3.23

# The monolithic mariadb package ships >100MB of binaries this stack never
# runs (embedded server, test client, RocksDB/Aria/MyISAM offline tools,
# binlog & benchmark utilities — the storage engines themselves live inside
# mariadbd). Dropped in the same layer to shrink the image and its export.
#
# The BuildKit cache mount keeps downloaded .apk files across
# package-layer changes (package-list edits, base-image bumps). Docker 29+
# discards cache mounts on --no-cache, keeping cold benchmarks honest; `apk update` always
# refreshes the index so a stale cache can never pin dropped versions.
ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-mariadb,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add mariadb mariadb-client \
    && rm /etc/apk/cache \
    && rm -f /usr/bin/mariadb-embedded /usr/bin/mysql_embedded \
        /usr/bin/test-connect-t /usr/bin/mariadb-ldb /usr/bin/sst_dump \
        /usr/bin/aria_* /usr/bin/myisam* \
        /usr/bin/mariadb-binlog /usr/bin/mysqlbinlog \
        /usr/bin/mariadb-slap /usr/bin/mysqlslap \
    && mkdir -p /run/mysqld /var/lib/mysql \
    && chown -R mysql:mysql /run/mysqld /var/lib/mysql

COPY conf/my.cnf /etc/my.cnf.d/mariadb-server.cnf
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 3306

# Healthy == the application user can connect over TCP, i.e. exactly what
# WordPress needs. During first-boot bootstrap (--skip-networking) this
# fails, keeping dependents waiting until the real server is up.
HEALTHCHECK --interval=3s --timeout=3s --start-period=30s --start-interval=500ms --retries=10 \
    CMD sh -c 'MYSQL_PWD="$(cat /run/secrets/db_password)" mariadb-admin ping -h 127.0.0.1 -u "$MYSQL_USER" --silent'

ENTRYPOINT ["entrypoint.sh"]
