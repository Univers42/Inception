# syntax=docker/dockerfile:1
FROM alpine:3.20

# Layer 1: System packages (cached unless Alpine version changes)
RUN apk add --no-cache \
        php83 \
        php83-fpm \
        php83-mysqli \
        php83-curl \
        php83-dom \
        php83-exif \
        php83-fileinfo \
        php83-mbstring \
        php83-openssl \
        php83-xml \
        php83-zip \
        php83-gd \
        php83-iconv \
        php83-intl \
        php83-simplexml \
        php83-sodium \
        php83-tokenizer \
        php83-xmlreader \
        php83-zlib \
        php83-phar \
        php83-ctype \
        php83-session \
        php83-opcache \
        php83-pecl-redis \
        wget \
        mariadb-client \
    && rm -rf /usr/share/man /usr/share/doc /tmp/* \
    && ln -sf /usr/bin/php83 /usr/bin/php \
    && mkdir -p /var/www/html \
    && chown -R nobody:nobody /var/www/html

# Layer 2: WP-CLI (separate layer — rarely changes)
RUN wget -q https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -O /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

# Layer 3: Pre-download WordPress core (avoids download on every first boot)
RUN su -s /bin/sh nobody -c 'wp core download --path=/var/www/html --skip-content'

# Layer 4: Config files (invalidated on config changes only)
COPY conf/www.conf /etc/php83/php-fpm.d/www.conf
COPY conf/opcache.ini /etc/php83/conf.d/00_opcache.ini
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
    CMD ["php-fpm83", "-t"]

ENTRYPOINT ["entrypoint.sh"]
