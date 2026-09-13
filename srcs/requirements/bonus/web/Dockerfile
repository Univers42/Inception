# srcs/requirements/bonus/web/Dockerfile
#
# Two stages:
#   build   — alpine + nodejs + npm: installs Astro from the committed lockfile
#             and renders the site to /app/dist. Thrown away entirely.
#   runtime — alpine + nginx, nothing else: serves the rendered bytes as the
#             unprivileged 'nginx' user. No node, no npm, no node_modules.
#
# Cache strategy (cheapest-changing layer first):
#   1. apk packages            — change with the Alpine pin only
#   2. package.json + lockfile — change when Astro is bumped
#   3. site sources            — change on every edit; only the render re-runs
FROM alpine:3.23 AS build

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
# nodejs — runs the Astro compiler;  npm — resolves the lockfile. Build stage only.
RUN --mount=type=cache,id=${APK_CACHE_ID}-web-build,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add nodejs npm \
    && rm /etc/apk/cache

WORKDIR /app
COPY app/package.json app/package-lock.json ./
RUN --mount=type=cache,id=npm-web,target=/root/.npm \
    npm ci --no-audit --no-fund --ignore-scripts

COPY app/ ./
RUN npm run build


FROM alpine:3.23

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
# nginx — the only daemon. The package creates the 'nginx' user the master
# process runs as; its temp/log directories are handed to that user because
# an unprivileged master cannot chown them at start.
RUN --mount=type=cache,id=${APK_CACHE_ID}-web,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add nginx \
    && rm /etc/apk/cache \
    && mkdir -p /usr/share/nginx/html /run/nginx \
    && chown -R nginx:nginx /var/lib/nginx /var/log/nginx /run/nginx

COPY conf/nginx.conf   /etc/nginx/nginx.conf
COPY conf/headers.conf /etc/nginx/headers.conf
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --from=build --chown=nginx:nginx /app/dist /usr/share/nginx/html/lab

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=4s --start-period=5s --start-interval=500ms --retries=3 \
    CMD ["wget", "-q", "--spider", "http://127.0.0.1:8080/lab/"]

COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ -x /usr/local/lib/inception-shell/hellish ] \
    || { echo "hellish is missing from the build context — run 'make setup' on a host that has it" >&2; exit 1; } \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/hellish \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/sh

USER nginx

ENTRYPOINT ["entrypoint.sh"]
