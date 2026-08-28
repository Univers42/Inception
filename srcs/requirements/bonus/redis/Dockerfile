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

ENTRYPOINT ["entrypoint.sh"]
