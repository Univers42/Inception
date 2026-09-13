# srcs/requirements/bonus/api/Dockerfile
#
# Two stages, one purpose each:
#   deps    — has npm, resolves the single runtime dependency (mysql2) from the
#             committed lockfile. Thrown away.
#   runtime — has node and nothing else. Receives server sources + node_modules.
#
# Cache strategy (cheapest-changing layer first):
#   1. apk packages            — change with the Alpine pin only
#   2. package.json + lockfile — change when a dependency is bumped
#   3. application sources     — change on every edit; only this layer rebuilds
FROM alpine:3.23 AS deps

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
# nodejs — runs npm;  npm — resolves the lockfile into node_modules. Neither
# reaches the runtime image.
RUN --mount=type=cache,id=${APK_CACHE_ID}-api-deps,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add nodejs npm \
    && rm /etc/apk/cache

WORKDIR /app
COPY app/package.json app/package-lock.json ./
# --omit=dev: nothing but mysql2 is installed;  --ignore-scripts: no postinstall
# code from the registry runs at build time.
RUN --mount=type=cache,id=npm-api,target=/root/.npm \
    npm ci --omit=dev --no-audit --no-fund --ignore-scripts


FROM alpine:3.23

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
# nodejs — the runtime. That is the whole list: no npm, no shell tooling.
# The 'api' user is who the server runs as after it has read its secret.
RUN --mount=type=cache,id=${APK_CACHE_ID}-api,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add nodejs \
    && rm /etc/apk/cache \
    && addgroup -S -g 1001 api \
    && adduser  -S -D -H -u 1001 -G api -s /sbin/nologin api

WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY app/*.js app/schema.sql app/package.json ./
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 3000

# Liveness is the API's own verdict on itself and its two backends.
HEALTHCHECK --interval=10s --timeout=4s --start-period=20s --start-interval=1s --retries=3 \
    CMD ["wget", "-q", "--spider", "http://127.0.0.1:3000/api/v1/healthz"]

COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ -x /usr/local/lib/inception-shell/hellish ] \
    || { echo "hellish is missing from the build context — run 'make setup' on a host that has it" >&2; exit 1; } \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/hellish \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/sh

ENTRYPOINT ["entrypoint.sh"]
