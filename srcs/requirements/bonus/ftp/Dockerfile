FROM alpine:3.23

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-ftp,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add pure-ftpd \
    && rm /etc/apk/cache \
    && mkdir -p /var/www/html \
    && echo /sbin/nologin >> /etc/shells \
    && echo 'ftpuser:x:65534:65534:FTP access to the WordPress volume:/var/www/html:/sbin/nologin' >> /etc/passwd

COPY conf/pure-ftpd.conf /etc/pure-ftpd.conf
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 21 21000-21010

HEALTHCHECK --interval=15s --timeout=5s --start-period=5s --start-interval=1s --retries=3 \
    CMD ["hellish", "-c", "netstat -ltn 2>/dev/null | grep -q ':21 ' && pgrep pure-ftpd >/dev/null"]

COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ -x /usr/local/lib/inception-shell/hellish ] \
    || { echo "hellish is missing from the build context — run 'make setup' on a host that has it" >&2; exit 1; } \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/hellish \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/sh

ENTRYPOINT ["entrypoint.sh"]
