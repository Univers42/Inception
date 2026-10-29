# srcs/requirements/bonus/staticsite/Dockerfile
#
# The subject's "static website in any language but PHP": the Inception landing
# (React + framer-motion, app/) and Deeper (React + three.js, world/). The edge
# nginx serves the landing at https://DOMAIN/ and Deeper at /deeper/; both stay
# published on 8090 as the bonus asks.
#
# The lab's pattern (bonus/web), one build stage per app:
#   build, build-world — alpine + nodejs + npm: the committed lockfile, then
#             `npm run build` (client bundle, server render, prerender).
#   runtime — alpine + nginx only. No node, no npm, no node_modules, no PHP.
#
# The design tokens and fonts come from srcs/design through the `design`
# additional build context, the same files the WordPress theme receives.
FROM alpine:3.23.7 AS build

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-staticsite-build,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add nodejs npm \
    && rm /etc/apk/cache

WORKDIR /src/app
COPY app/package.json app/package-lock.json ./
RUN --mount=type=cache,id=npm-staticsite,target=/root/.npm \
    npm ci --no-audit --no-fund --ignore-scripts

COPY --from=design / /src/design/
ENV DESIGN_DIR=/src/design
COPY app/ ./
RUN npm run build


# Deeper (world/), the immersive descent served under /deeper/. Its own stage,
# not a second build in the one above: BuildKit runs both at once, and editing
# one app leaves the other's cached layers alone.
FROM alpine:3.23.7 AS build-world

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-staticsite-build,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add nodejs npm \
    && rm /etc/apk/cache

WORKDIR /src/world
COPY world/package.json world/package-lock.json ./
RUN --mount=type=cache,id=npm-staticsite,target=/root/.npm \
    npm ci --no-audit --no-fund --ignore-scripts

COPY --from=design / /src/design/
ENV DESIGN_DIR=/src/design
COPY world/ ./
RUN npm run build


FROM alpine:3.23.7

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-staticsite,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add nginx \
    && rm /etc/apk/cache \
    && mkdir -p /run/nginx

COPY conf/nginx.conf /etc/nginx/http.d/default.conf
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --from=build /src/app/dist/ /usr/share/nginx/html/
COPY --from=build-world /src/world/dist/ /usr/share/nginx/html/deeper/

EXPOSE 8090

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --start-interval=500ms --retries=3 \
    CMD ["wget", "--spider", "-q", "http://localhost:8090/"]

COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ -x /usr/local/lib/inception-shell/hellish ] \
    || { echo "hellish is missing from the build context — run 'make setup' on a host that has it" >&2; exit 1; } \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/hellish \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/sh

ENTRYPOINT ["entrypoint.sh"]
