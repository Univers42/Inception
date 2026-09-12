FROM alpine:3.23

# the ARG declares build-time variable- only avialble while the image is being built
# during docker build, not at container runtime
# the build time variable dissapear once the image is built - it's not baked into the container's environment like ENV is
ARG APK_CACHE_ID=apk
# Docker caches each RUN layer based on the instruction's exact text:
# # if nothing changed, it resuses the cached layer instead of re-running apk update && apk add ...,
# so packages can go stale silently.
# CACHE BUST is referenced inside the RUN line via "bust=${CACHE_BUST}"
#  a no-op that just embeds the arg's value intot the intstruction text. Change CACHE_BUST (e.g. --build-arg
#  CACHE_BUST=$(date +%s)) and Docker sees a different instruction string, so it invalidtates the cache
#  and actually re-runs apk update/apk add, pulling resh package version of resuing an old cache layer.
ARG CACHE_BUST=0
# --mount=type=cache is a BuildKit cache mount. It can only attach to one
# exact path (target=/var/cache/apk):
# https://docs.docker.com/reference/dockerfile/#run---mounttypecache
# apk caches packages at /etc/apk/cache by default, so that path is symlinked
# onto the mount for the duration of the step and the symlink is removed
# afterwards, so no dangling symlink is left in the image.
# Alpine's default nginx config ships its own ssl_protocols line (often with
# older TLS versions). The sed rewrites it in place to force TLS 1.2/1.3 only,
# satisfying the subject's TLS requirement without hand-writing nginx.conf.
# /run/nginx holds nginx's runtime PID/socket files; /etc/nginx/ssl is where
# the entrypoint script copies the cert and key.
RUN --mount=type=cache,id=${APK_CACHE_ID}-nginx,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add nginx \
    && sed -i 's/^\([[:space:]]*\)ssl_protocols .*/\1ssl_protocols TLSv1.2 TLSv1.3;/' /etc/nginx/nginx.conf \
    && rm /etc/apk/cache \
    && mkdir -p \
        /run/nginx \
        /etc/nginx/ssl

# configuration repo's config
COPY conf/nginx.conf /etc/nginx/http.d/default.conf.template
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 443

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --start-interval=500ms --retries=3 \
    CMD ["wget", "--no-check-certificate", "--spider", "-q", "https://localhost:443/"]

COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ -x /usr/local/lib/inception-shell/hellish ] \
    || { echo "hellish is missing from the build context — run 'make setup' on a host that has it" >&2; exit 1; } \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/hellish \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/sh

ENTRYPOINT ["entrypoint.sh"]
