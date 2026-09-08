FROM alpine:3.23

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-dbbackup,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add mariadb-client \
    && rm /etc/apk/cache \
    && mkdir -p /backups

COPY --chmod=755 tools/backup.sh  /usr/local/bin/backup.sh
COPY --chmod=755 tools/restore.sh /usr/local/bin/restore.sh
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --start-interval=2s --retries=3 \
    CMD ["hellish", "-c", "ls /backups/*.sql.gz >/dev/null 2>&1 && gzip -t \"$(ls -t /backups/*.sql.gz | head -1)\""]

COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ -x /usr/local/lib/inception-shell/hellish ] \
    || { echo "hellish is missing from the build context — run 'make setup' on a host that has it" >&2; exit 1; } \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/hellish \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/sh

ENTRYPOINT ["entrypoint.sh"]
