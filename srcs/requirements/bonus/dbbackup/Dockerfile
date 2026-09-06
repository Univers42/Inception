# Bonus (free choice) — scheduled, verified backups of the WordPress database.
#
# Why this one: the subject requires both volumes to live on the host precisely
# because the data is what matters. Nothing else in the stack protects it. A
# container can be rebuilt from a Dockerfile in seconds; the database cannot be
# rebuilt from anything.
FROM alpine:3.23

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-dbbackup,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    # mariadb-client for mariadb-dump; busybox already provides crond and gzip.
    && apk add mariadb-client \
    && rm /etc/apk/cache \
    && mkdir -p /backups

COPY --chmod=755 tools/backup.sh  /usr/local/bin/backup.sh
COPY --chmod=755 tools/restore.sh /usr/local/bin/restore.sh
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

# Healthy == a readable, non-empty, gzip-valid dump exists. A backup service
# whose only claim is "the process is running" is exactly the kind that is
# discovered to be broken on the day it is needed.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --start-interval=2s --retries=3 \
    CMD ["sh", "-c", "ls /backups/*.sql.gz >/dev/null 2>&1 && gzip -t \"$(ls -t /backups/*.sql.gz | head -1)\""]

# The shell that runs this container's scripts: the entrypoint, the
# healthcheck's `sh -c`, whatever `docker exec ... sh` is asked. `make setup`
# drops the static shell the host was built with into srcs/shell/ when it has
# one (hellish, in the born2root guest), and /bin/sh becomes that; with nothing
# there, busybox's sh stays. Last, so every package script above ran under the
# shell it was written for.
COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ ! -x /usr/local/lib/inception-shell/sh ] || ln -sf /usr/local/lib/inception-shell/sh /bin/sh

ENTRYPOINT ["entrypoint.sh"]
