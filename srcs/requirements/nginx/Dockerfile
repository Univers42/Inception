# Penultimate stable Alpine (subject requirement) — latest stable is 3.24
FROM alpine:3.23

# Single package: TLS material is issued on the host and mounted as secrets,
# and the vhost template is rendered with sed — no openssl/gettext needed.
#
# The BuildKit cache mount keeps downloaded .apk files across
# package-layer changes (package-list edits, base-image bumps). Docker 29+
# discards cache mounts on --no-cache, so benchmarked cold builds stay
# honest; virgin machines start empty and are unaffected. `apk update` always refreshes the index so a stale cache
# can never pin dropped package versions.
ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-nginx,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add nginx \
    && rm /etc/apk/cache \
    && mkdir -p /run/nginx /etc/nginx/ssl

COPY conf/nginx.conf /etc/nginx/http.d/default.conf.template
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 443

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --start-interval=500ms --retries=3 \
    CMD ["wget", "--no-check-certificate", "--spider", "-q", "https://localhost:443/"]

ENTRYPOINT ["entrypoint.sh"]
