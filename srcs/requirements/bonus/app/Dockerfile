FROM alpine:3.22

# Role: installing the node, npm, pnpm dependencis. The Dockerfile already does that

RUN apk add --no-cache \
	nodejs \
	npm \
	ca-certificates

WORKDIR /app

RUN npm install -g pnpm

COPY site/package.json ./site/
COPY site/pnpm-workspace.yaml ./site/

WORKDIR /app/site

RUN pnpm install

WORKDIR /app

COPY site ./site
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
