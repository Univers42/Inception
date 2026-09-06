# Bonus — Adminer, a single-file database front end for MariaDB.
#
# Adminer is PHP. That is fine here: the "no PHP" rule in the subject applies to
# the static-website bonus, not to this one.
FROM alpine:3.23

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-adminer,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add php84 php84-mysqli php84-session \
    && rm /etc/apk/cache \
    && ln -sf /usr/bin/php84 /usr/bin/php \
    && mkdir -p /var/www/adminer

# Pinned version AND pinned hash. A bare download of "latest" would make the
# image contents change under you between builds, and this one talks to the
# database — so its integrity is checked rather than assumed.
ARG ADMINER_VERSION=5.3.0
ARG ADMINER_SHA256=7dcc196e941b18b74635afe1740dcd86970ab08b8eba0f00f149925aea3972ed
ARG DL_CACHE_ID=dl
RUN --mount=type=cache,id=${DL_CACHE_ID}-adminer,sharing=locked,target=/dl \
    : "bust=${CACHE_BUST}" \
    && { [ -f "/dl/adminer-${ADMINER_VERSION}.php" ] || { \
           wget -qO "/dl/.adminer.tmp" \
             "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php" \
           && mv "/dl/.adminer.tmp" "/dl/adminer-${ADMINER_VERSION}.php"; }; } \
    && echo "${ADMINER_SHA256}  /dl/adminer-${ADMINER_VERSION}.php" | sha256sum -c - \
    && install -m 0444 "/dl/adminer-${ADMINER_VERSION}.php" /var/www/adminer/index.php

COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --start-interval=500ms --retries=3 \
    CMD ["wget", "--spider", "-q", "http://127.0.0.1:8080/"]

# The shell that runs this container's scripts: the entrypoint, the
# healthcheck's `sh -c`, whatever `docker exec ... sh` is asked. `make setup`
# drops the static shell the host was built with into srcs/shell/ when it has
# one (hellish, in the born2root guest), and /bin/sh becomes that; with nothing
# there, busybox's sh stays. Last, so every package script above ran under the
# shell it was written for.
COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ ! -x /usr/local/lib/inception-shell/sh ] || ln -sf /usr/local/lib/inception-shell/sh /bin/sh

ENTRYPOINT ["entrypoint.sh"]
