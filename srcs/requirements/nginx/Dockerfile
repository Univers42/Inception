# syntax=docker/dockerfile:1
FROM alpine:3.20

# Single layer: install + cleanup
RUN apk add --no-cache \
        nginx \
        openssl \
    && rm -rf /usr/share/man /usr/share/doc /tmp/* \
    && mkdir -p /etc/nginx/ssl /run/nginx

COPY conf/nginx.conf /etc/nginx/http.d/default.conf.template
COPY --chmod=755 tools/entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 443

HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD ["wget", "--no-check-certificate", "--spider", "-q", "https://localhost:443/"]

ENTRYPOINT ["entrypoint.sh"]
