# syntax=docker/dockerfile:1
FROM alpine:3.20

# Single layer: install + cleanup + dir setup
RUN apk add --no-cache \
        mariadb \
        mariadb-client \
    && rm -rf /usr/share/man /usr/share/doc /tmp/* \
    && mkdir -p /run/mysqld /var/lib/mysql \
    && chown -R mysql:mysql /run/mysqld /var/lib/mysql

# COPY --chmod avoids an extra RUN chmod layer
COPY conf/my.cnf /etc/my.cnf.d/mariadb-server.cnf
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 3306

HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD ["mysqladmin", "ping", "-h", "localhost", "--silent"]

ENTRYPOINT ["entrypoint.sh"]
