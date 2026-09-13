# srcs/requirements/bonus/nodetool/Dockerfile
#
# nodetool — the project's only node + npm. Nothing Node-related runs on the
# host: lockfiles are resolved, and any npm command is executed, inside this
# image with the app directory bind-mounted (`make lock`,
# `make npm-web NPM="..."`, `make npm-api NPM="..."`). It is the same
# alpine:3.23 + apk nodejs/npm pair the web and api build stages use, so what
# resolves here is exactly what the image builds install.
#
# Like 42ctl, this is NOT a docker-compose service, and that is deliberate: npm
# exits when its command finishes, and an Inception service must run a real
# daemon as PID 1 with no keep-alive hack (compliance S06/S18/S23, R10/R19).
FROM alpine:3.23

ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-nodetool,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add nodejs npm \
    && rm /etc/apk/cache

# The app directory is mounted here. The uid is chosen at `docker run` time so
# the files npm writes belong to the developer on the host, rootless or not;
# npm's own cache stays inside the container and dies with it.
WORKDIR /app
ENV HOME=/tmp \
    npm_config_cache=/tmp/npm-cache \
    npm_config_update_notifier=false

ENTRYPOINT ["npm"]
