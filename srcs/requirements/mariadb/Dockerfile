FROM alpine:3.23

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

HEALTHCHECK --interval=3s --timeout=3s --start-period=30s --start-interval=500ms --retries=10 \
    CMD sh -c 'MYSQL_PWD="$(cat /run/secrets/db_password)" mariadb-admin ping -h 127.0.0.1 -u "$MYSQL_USER" --silent'

COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ ! -x /usr/local/lib/inception-shell/sh ] || ln -sf /usr/local/lib/inception-shell/sh /bin/sh

ENTRYPOINT ["entrypoint.sh"]
