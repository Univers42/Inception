FROM alpine:3.23 AS wp-src

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

COPY --from=wp-src --chown=nobody:nobody /usr/src/wordpress /usr/src/wordpress
COPY --from=wp-src /usr/local/bin/wp /usr/local/bin/wp

COPY conf/www.conf /etc/php84/php-fpm.d/www.conf
COPY conf/opcache.ini conf/uploads.ini /etc/php84/conf.d/
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

COPY site/ /usr/src/inception-site/

WORKDIR /var/www/html

EXPOSE 9000

# Observe the listening socket instead of connecting to it (same rule as the
# FTP healthcheck). php-fpm counts every connection it accepts, an empty one
# included, and the lab's traffic view reads that counter: an nc -z every 3 s
# drew a request that never happened on the nginx → wordpress wire. It is no
# weaker a check: the kernel completes nc's handshake from the listen backlog
# whether or not php-fpm is able to serve.
HEALTHCHECK --interval=3s --timeout=3s --start-period=60s --start-interval=500ms --retries=10 \
    CMD ["hellish", "-c", "netstat -ltn 2>/dev/null | grep -q ':9000 ' && pgrep php-fpm84 >/dev/null"]

COPY --from=shell / /usr/local/lib/inception-shell/
RUN [ -x /usr/local/lib/inception-shell/hellish ] \
    || { echo "hellish is missing from the build context — run 'make setup' on a host that has it" >&2; exit 1; } \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/hellish \
    && ln -sf /usr/local/lib/inception-shell/hellish /bin/sh

ENTRYPOINT ["entrypoint.sh"]
