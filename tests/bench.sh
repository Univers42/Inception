#!/bin/sh
# ═════════════════════════════════════════════════════════════════════
#  Inception — build & boot benchmarks
#
#  Usage:  sh tests/bench.sh [--with-boot]
#
#  Default: build benchmarks only (safe, leaves data untouched).
#    1. true cold   — --no-cache --pull with EMPTY package caches: the
#                     Dockerfiles use BuildKit cache mounts, so this run
#                     points them at dedicated "bench-cold" cache IDs that
#                     are wiped (untimed) beforehand. This is the honest
#                     virgin-machine number.
#    2. pkg-cached  — every package layer re-runs (CACHE_BUST build arg,
#                     the same effect as editing a package list or bumping
#                     the base image) but .apk files and the WP tarball
#                     come from the warm BuildKit cache mounts. Docker 29+
#                     discards those mounts on --no-cache, so this — not
#                     --no-cache — is the scenario where they engage.
#                     First ever run populates the cache (≈ true cold).
#    3. warm        — rebuild after touching every conf file
#    4. no-op       — rebuild with nothing changed
#
#  --with-boot additionally measures first boot to a live site.
#  ⚠  --with-boot WIPES /home/<login>/data (fresh-install timing).
# ═════════════════════════════════════════════════════════════════════
set -u
cd "$(dirname "$0")/.." || exit 1

export DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 COMPOSE_BAKE=true
export BUILDX_NO_DEFAULT_ATTESTATIONS=1
COMPOSE="docker compose -f srcs/docker-compose.yml"
LOGIN=$(sed -n 's/^LOGIN[[:space:]]*=[[:space:]]*//p' Makefile | head -1)
DOMAIN=$(sed -n 's/^DOMAIN_NAME=//p' srcs/.env 2>/dev/null | head -1)
[ -n "$DOMAIN" ] || DOMAIN="$LOGIN.42.fr"
DATA_DIR="/home/$LOGIN/data"

t() { date +%s.%N; }
dur() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", b-a}'; }

echo "══ Inception benchmarks ══"
echo "host: $(nproc) cpus, $(free -m 2>/dev/null | awk '/^Mem:/{print $2}')MB RAM, docker $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
echo

# wipe the bench-only cache mounts (untimed) so run 1 is honestly cold;
# a fixed ID + in-place clear avoids orphaning cache records in BuildKit
BUST=bench-cold
printf 'FROM alpine:3.23\nRUN --mount=type=cache,id=%s-nginx,target=/c1 --mount=type=cache,id=%s-mariadb,target=/c2 --mount=type=cache,id=%s-wordpress,target=/c3 --mount=type=cache,id=%s-wpsrc,target=/c4 rm -rf /c1/* /c2/* /c3/* /c4/*\n' \
    "$BUST" "$BUST" "$BUST" "$BUST" | docker build --no-cache -q - >/dev/null 2>&1

S=$(t); $COMPOSE build --no-cache --pull \
    --build-arg APK_CACHE_ID=$BUST --build-arg DL_CACHE_ID=$BUST >/dev/null 2>&1; E=$(t)
COLD=$(dur "$S" "$E")
echo "true cold   (empty pkg caches)  : ${COLD}s"

S=$(t); $COMPOSE build --pull --build-arg CACHE_BUST="bench-$(date +%s)" >/dev/null 2>&1; E=$(t)
CCOLD=$(dur "$S" "$E")
echo "pkg-cached  (layers re-run, warm caches) : ${CCOLD}s  (first ever run populates the cache)"

touch srcs/requirements/nginx/conf/nginx.conf \
      srcs/requirements/wordpress/conf/www.conf \
      srcs/requirements/mariadb/conf/my.cnf
S=$(t); $COMPOSE build >/dev/null 2>&1; E=$(t)
WARM=$(dur "$S" "$E")
echo "warm build  (all confs touched) : ${WARM}s"

S=$(t); $COMPOSE build >/dev/null 2>&1; E=$(t)
NOOP=$(dur "$S" "$E")
echo "no-op build (nothing changed)   : ${NOOP}s"

echo
echo "image sizes:"
docker images --format '  {{.Repository}}:{{.Tag}}  {{.Size}}' | grep ':inception'

if [ "${1:-}" = "--with-boot" ]; then
    echo
    echo "boot benchmark — wiping $DATA_DIR for a fresh install ..."
    $COMPOSE down >/dev/null 2>&1
    docker run --rm -v "$DATA_DIR":/d alpine:3.23 sh -c 'rm -rf /d/mariadb /d/wordpress' >/dev/null 2>&1 \
        || sudo rm -rf "$DATA_DIR/mariadb" "$DATA_DIR/wordpress"
    mkdir -p "$DATA_DIR/mariadb" "$DATA_DIR/wordpress"

    S=$(t)
    $COMPOSE up -d >/dev/null 2>&1
    CODE=000; i=0
    while [ $i -lt 360 ]; do
        CODE=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 2 "https://$DOMAIN/" 2>/dev/null || echo 000)
        [ "$CODE" = "200" ] && break
        sleep 0.5; i=$((i+1))
    done
    E=$(t)
    echo "first boot → live site (fresh volumes, WP installed) : $(dur "$S" "$E")s (http $CODE)"

    S=$(t)
    $COMPOSE restart >/dev/null 2>&1
    CODE=000; i=0
    while [ $i -lt 120 ]; do
        CODE=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 2 "https://$DOMAIN/" 2>/dev/null || echo 000)
        [ "$CODE" = "200" ] && break
        sleep 0.5; i=$((i+1))
    done
    E=$(t)
    echo "warm restart → live site (existing data)             : $(dur "$S" "$E")s (http $CODE)"
fi
