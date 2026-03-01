# syntax=docker/dockerfile:1
FROM alpine:3.20

# Single layer: install + cleanup + harden main config
RUN apk add --no-cache \
        nginx \
        openssl \
        gettext \
    && rm -rf /usr/share/man /usr/share/doc /tmp/* \
    && mkdir -p /etc/nginx/ssl /run/nginx \
    && sed -i 's/ssl_protocols .*/ssl_protocols TLSv1.2 TLSv1.3;/' /etc/nginx/nginx.conf

COPY conf/nginx.conf /etc/nginx/http.d/default.conf.template
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 443

HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD ["wget", "--no-check-certificate", "--spider", "-q", "https://localhost:443/"]

ENTRYPOINT ["entrypoint.sh"]
