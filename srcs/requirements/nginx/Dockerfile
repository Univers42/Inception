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
    # Alpine's stock nginx.conf declares "ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3"
    # at http level. Our server block overrides it, so the handshake already
    # refuses TLSv1.1 — but `nginx -T` still shows the obsolete protocol in the
    # effective config, which is the first thing an audit greps for. Pin the
    # inherited default to match, so there is only one answer anywhere.
    && sed -i 's/^\([[:space:]]*\)ssl_protocols .*/\1ssl_protocols TLSv1.2 TLSv1.3;/' /etc/nginx/nginx.conf \
    && rm /etc/apk/cache \
    && mkdir -p /run/nginx /etc/nginx/ssl

COPY conf/nginx.conf /etc/nginx/http.d/default.conf.template
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 443

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --start-interval=500ms --retries=3 \
    CMD ["wget", "--no-check-certificate", "--spider", "-q", "https://localhost:443/"]

# The shell that runs this container's scripts: the entrypoint, the
# healthcheck's `sh -c`, whatever `docker exec ... sh` is asked. `make setup`
# drops the static shell the host was built with into srcs/shell/ when it has
# one (hellish, in the born2root guest), and /bin/sh becomes that; with nothing
# there, busybox's sh stays. Last, so every package script above ran under the
# shell it was written for.
COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ ! -x /usr/local/lib/inception-shell/sh ] || ln -sf /usr/local/lib/inception-shell/sh /bin/sh

ENTRYPOINT ["entrypoint.sh"]
