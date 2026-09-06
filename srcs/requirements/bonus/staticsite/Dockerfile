# Bonus — static showcase site (subject rule: any language except PHP).
# Content is plain HTML/CSS/vanilla JS; nginx here only serves those files —
# no PHP, no app server, no framework. Same base as the rest of the project.
FROM alpine:3.23

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
COPY site/ /usr/share/nginx/html/

EXPOSE 8090

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --start-interval=500ms --retries=3 \
    CMD ["wget", "--spider", "-q", "http://localhost:8090/"]

# The shell that runs this container's scripts: the entrypoint, the
# healthcheck's `sh -c`, whatever `docker exec ... sh` is asked. `make setup`
# drops the static shell the host was built with into srcs/shell/ when it has
# one (hellish, in the born2root guest), and /bin/sh becomes that; with nothing
# there, busybox's sh stays. Last, so every package script above ran under the
# shell it was written for.
COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ ! -x /usr/local/lib/inception-shell/sh ] || ln -sf /usr/local/lib/inception-shell/sh /bin/sh

ENTRYPOINT ["entrypoint.sh"]
