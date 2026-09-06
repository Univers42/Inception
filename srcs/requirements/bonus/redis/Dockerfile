# Bonus — Redis, used as WordPress's persistent object cache.
#
# WordPress rebuilds the same option/post/term objects from MariaDB on every
# request. With the object cache in place those live in memory instead, so a
# page render stops being dozens of small queries. Same base and same apk cache
# mount as the rest of the project.
FROM alpine:3.23

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-redis,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add redis \
    && rm /etc/apk/cache

COPY conf/redis.conf /etc/redis.conf
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

# Not published in docker-compose.yml: reachable only from the inception
# network. A cache with no authentication must never be exposed to a host port.
EXPOSE 6379

HEALTHCHECK --interval=10s --timeout=3s --start-period=3s --start-interval=500ms --retries=3 \
    CMD ["sh", "-c", "redis-cli ping | grep -q PONG"]

# The shell that runs this container's scripts: the entrypoint, the
# healthcheck's `sh -c`, whatever `docker exec ... sh` is asked. `make setup`
# drops the static shell the host was built with into srcs/shell/ when it has
# one (hellish, in the born2root guest), and /bin/sh becomes that; with nothing
# there, busybox's sh stays. Last, so every package script above ran under the
# shell it was written for.
COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ ! -x /usr/local/lib/inception-shell/sh ] || ln -sf /usr/local/lib/inception-shell/sh /bin/sh

ENTRYPOINT ["entrypoint.sh"]
