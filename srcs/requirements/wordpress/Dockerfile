# Penultimate stable Alpine (subject requirement) — latest stable is 3.24
#
# Side stage: WordPress core + WP-CLI are fetched here so the downloads and
# extraction run IN PARALLEL with the PHP package installation below
# (BuildKit builds independent stages concurrently). Native tar extraction
# is also far faster than WP-CLI's PHP-based unzip and needs no
# memory-limit override. Integrity is still verified at runtime via
# `wp core verify-checksums` (make run_wp).
FROM alpine:3.23 AS wp-src

# The cache mount keeps the WP tarball + WP-CLI across package-layer
# changes (downloads are atomic: tmp file + rename, so an aborted fetch can
# never poison the cache). Docker 29+ discards cache mounts on --no-cache.
ARG DL_CACHE_ID=dl
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${DL_CACHE_ID}-wpsrc,sharing=locked,target=/dl \
    : "bust=${CACHE_BUST}" \
    && { [ -f /dl/wp.tar.gz ] || { wget -qO /dl/.wp.tmp https://wordpress.org/latest.tar.gz \
        && mv /dl/.wp.tmp /dl/wp.tar.gz; }; } \
    && { [ -f /dl/wp-cli.phar ] || { wget -qO /dl/.cli.tmp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        && mv /dl/.cli.tmp /dl/wp-cli.phar; }; } \
    && mkdir -p /usr/src \
    && tar -xzf /dl/wp.tar.gz -C /usr/src \
    && install -m 0755 /dl/wp-cli.phar /usr/local/bin/wp

FROM alpine:3.23

# Layer 1: PHP runtime + every extension WordPress needs (cached until the
# Alpine version changes). busybox wget handles HTTPS, and the MariaDB wait
# is done with php-mysqli, so neither wget nor mariadb-client is installed.
# The apk cache mount mirrors the nginx/mariadb Dockerfiles (see there).
ARG APK_CACHE_ID=apk
ARG CACHE_BUST=0
RUN --mount=type=cache,id=${APK_CACHE_ID}-wordpress,sharing=locked,target=/var/cache/apk \
    : "bust=${CACHE_BUST}" \
    && ln -sf /var/cache/apk /etc/apk/cache \
    && apk update -q \
    && apk add \
        php84 \
        php84-fpm \
        php84-mysqli \
        php84-curl \
        php84-dom \
        php84-exif \
        php84-fileinfo \
        php84-mbstring \
        php84-openssl \
        php84-xml \
        php84-zip \
        php84-gd \
        php84-iconv \
        php84-intl \
        php84-simplexml \
        php84-sodium \
        php84-tokenizer \
        php84-xmlreader \
        php84-zlib \
        php84-phar \
        php84-ctype \
        php84-session \
        php84-opcache \
        php84-pecl-redis \
    && rm /etc/apk/cache \
    && ln -sf /usr/bin/php84 /usr/bin/php \
    && mkdir -p /var/www/html \
    && chown nobody:nobody /var/www/html \
    && sed -i 's|^;*error_log = .*|error_log = /proc/self/fd/2|' /etc/php84/php-fpm.conf

# Layer 2: full WordPress core (themes included) + WP-CLI from the parallel
# stage. First boot copies /usr/src/wordpress into the volume — zero
# network, deterministic, immune to volume copy-up semantics.
COPY --from=wp-src --chown=nobody:nobody /usr/src/wordpress /usr/src/wordpress
COPY --from=wp-src /usr/local/bin/wp /usr/local/bin/wp

# Layer 3: config files (invalidated on config changes only)
COPY conf/www.conf /etc/php84/php-fpm.d/www.conf
COPY conf/opcache.ini conf/uploads.ini /etc/php84/conf.d/
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

# Layer 5: documentation site — custom theme, plugin and seed content.
# Deployed by the entrypoint via site/install.sh (idempotent, non-fatal).
COPY site/ /usr/src/inception-site/

WORKDIR /var/www/html

EXPOSE 9000

# Healthy == php-fpm is accepting FastCGI connections. The long start
# period covers the one-time WordPress installation on first boot.
HEALTHCHECK --interval=3s --timeout=3s --start-period=60s --start-interval=500ms --retries=10 \
    CMD ["nc", "-z", "127.0.0.1", "9000"]

ENTRYPOINT ["entrypoint.sh"]
