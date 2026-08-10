#!/bin/sh
# ═════════════════════════════════════════════════════════════════════
#  Inception — TODO.md verification suite
#
#  Every check maps 1:1 to a line in TODO.md, so a tick in that file is
#  never a claim: it is the output of a command anyone can re-run.
#
#  Usage:  sh tests/todo.sh            (or: make todo)
#
#  Exit code = number of failed checks.
#  A check is only PASS when it was actually proven. When something
#  cannot be tested in this environment it reports BLOCKED with the
#  reason and the remediation — never a silent pass.
# ═════════════════════════════════════════════════════════════════════
set -u

cd "$(dirname "$0")/.." || exit 1

if [ -t 1 ]; then
    RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
    BLU='\033[1;34m'; DIM='\033[2m'; RST='\033[0m'
else
    RED=''; GRN=''; YLW=''; BLU=''; DIM=''; RST=''
fi

PASS=0; FAIL=0; BLOCK=0
pass()  { PASS=$((PASS+1));  printf "  ${GRN}✔${RST} %-6s %s\n" "$1" "$2"; [ -n "${3:-}" ] && printf "         ${DIM}%s${RST}\n" "$3"; return 0; }
fail()  { FAIL=$((FAIL+1));  printf "  ${RED}✘${RST} %-6s %s\n" "$1" "$2"; [ -n "${3:-}" ] && printf "         ${DIM}%s${RST}\n" "$3"; return 0; }
block() { BLOCK=$((BLOCK+1)); printf "  ${YLW}⊘${RST} %-6s %s\n" "$1" "$2"; [ -n "${3:-}" ] && printf "         ${DIM}%s${RST}\n" "$3"; return 0; }
section() { printf "\n${BLU}%s${RST}\n" "$1"; }

# ── Context ──────────────────────────────────────────────────────────
LOGIN=$(sed -n 's/^LOGIN[[:space:]]*=[[:space:]]*//p' Makefile | head -1)
[ -n "$LOGIN" ] || LOGIN=$(whoami)
DOMAIN=$(sed -n 's/^DOMAIN_NAME=//p' srcs/.env 2>/dev/null | head -1)
[ -n "$DOMAIN" ] || DOMAIN="$LOGIN.42.fr"
COMPOSE_FILE=srcs/docker-compose.yml
SERVICES="nginx wordpress mariadb"
DOCKERFILES="srcs/requirements/nginx/Dockerfile srcs/requirements/wordpress/Dockerfile srcs/requirements/mariadb/Dockerfile"
ENTRYPOINTS="srcs/requirements/nginx/tools/entrypoint.sh srcs/requirements/wordpress/tools/entrypoint.sh srcs/requirements/mariadb/tools/entrypoint.sh"
DATA_DIR="/home/$LOGIN/data"
BASE_IMAGE=$(grep -h '^FROM' $DOCKERFILES | awk '{print $2}' | sort -u | head -1)
PROBE_IMG=inception-probe:test

RUNNING=1
for c in $SERVICES; do
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$c" || RUNNING=0
done

printf "${BLU}══ Inception — TODO.md verification ══${RST}  login=%s domain=%s stack=%s\n" \
    "$LOGIN" "$DOMAIN" "$([ $RUNNING -eq 1 ] && echo up || echo down)"

# ── HTTPS probing ────────────────────────────────────────────────────
# Preferred path is the host talking to the published port, exactly as a
# grader would. Where the host cannot reach it — rootless Docker refuses
# to bind privileged ports — we fall back to a throwaway container on the
# inception network, which exercises the same nginx, vhost, certificate
# and port 443. PROBE_MODE records which path was used so no result is
# ever reported as something it is not.
PROBE_MODE=none
probe_setup() {
    [ $RUNNING -eq 1 ] || return 1
    if curl -ks --max-time 4 -o /dev/null "https://$DOMAIN/" 2>/dev/null; then
        PROBE_MODE=host
        return 0
    fi
    NGINX_IP=$(docker inspect nginx --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
    [ -n "$NGINX_IP" ] || return 1
    if ! docker image inspect "$PROBE_IMG" >/dev/null 2>&1; then
        printf 'FROM %s\nRUN apk add --no-cache curl openssl\n' "$BASE_IMAGE" \
            | docker build -q -t "$PROBE_IMG" - >/dev/null 2>&1 || return 1
    fi
    PROBE_MODE=network
    return 0
}
# probe <shell snippet using $D as the domain>
probe() {
    case "$PROBE_MODE" in
        host)    D="$DOMAIN" sh -c "D=$DOMAIN; $1" ;;
        network) docker run --rm --network inception \
                    --add-host "$DOMAIN:$NGINX_IP" "$PROBE_IMG" \
                    sh -c "D=$DOMAIN; $1" 2>/dev/null ;;
        *)       return 1 ;;
    esac
}
probe_note() {
    [ "$PROBE_MODE" = "network" ] && echo "probed from a container on the inception network (host cannot bind :443 here)" || echo ""
}

probe_setup || true

# ── compose helper: print one service block ──────────────────────────
svc_block() {
    awk -v tgt="  $1:" '$0==tgt{f=1;next} f && /^  [a-zA-Z0-9_-]+:[[:space:]]*$/{f=0} f' "$COMPOSE_FILE"
}

# ═════════════════════════════════════════════════════════════════════
section "Docker Compose, images and base OS"
# ═════════════════════════════════════════════════════════════════════

# T01 — do we use docker-compose?
if [ -f "$COMPOSE_FILE" ] && grep -q 'docker compose -f srcs/docker-compose.yml' Makefile; then
    NSVC=$(awk '/^services:/{f=1;next} /^[a-z]/{f=0} f && /^  [a-zA-Z0-9_-]+:[[:space:]]*$/{n++} END{print n+0}' "$COMPOSE_FILE")
    pass T01 "docker compose is used, and the Makefile drives it" \
        "$COMPOSE_FILE defines $NSVC services; Makefile calls compose with this file"
else
    fail T01 "no docker-compose.yml driven by the Makefile"
fi

# T02 — image name == service name
ok=1; detail=""
for s in $SERVICES; do
    img=$(svc_block "$s" | sed -n 's/^ *image: *//p' | head -1)
    case "$img" in
        "$s":*) detail="$detail $img" ;;
        *) ok=0; fail T02 "image for service '$s' is '$img' (must be '$s:<tag>')" ;;
    esac
done
[ $ok -eq 1 ] && pass T02 "every image is named after its service" "$detail"

# T03 — one service per dedicated container
if [ $RUNNING -eq 1 ]; then
    ok=1; detail=""
    for s in $SERVICES; do
        cid=$(docker ps --filter "name=^${s}$" --format '{{.ID}}')
        [ -n "$cid" ] || { ok=0; fail T03 "no dedicated container running for $s"; }
        detail="$detail $s"
    done
    # and each container runs exactly one service daemon as PID 1
    for pair in "nginx:nginx" "wordpress:php-fpm84" "mariadb:mariadbd"; do
        c=${pair%%:*}; d=${pair#*:}
        p1=$(docker exec "$c" ps -o pid,comm 2>/dev/null | awk '$1==1{print $2}')
        [ "$p1" = "$d" ] || { ok=0; fail T03 "$c PID 1 is '$p1', expected $d"; }
    done
    [ $ok -eq 1 ] && pass T03 "each service runs in its own container, as PID 1" "$detail"
else
    block T03 "stack is down — start it with 'make up'"
fi

# T04 — penultimate stable version of the base OS
NBASE=$(grep -h '^FROM' $DOCKERFILES | awk '{print $2}' | sort -u | wc -l)
LATEST=$(curl -fsS --max-time 8 "https://hub.docker.com/v2/repositories/library/alpine/tags?page_size=100&name=3." 2>/dev/null \
         | tr ',' '\n' | sed -n 's/.*"name":"\(3\.[0-9][0-9]*\)".*/\1/p' | sort -t. -k2 -n | uniq | tail -1)
if [ "$NBASE" != "1" ]; then
    fail T04 "the three Dockerfiles must share one pinned base" "$(grep -h '^FROM' $DOCKERFILES | awk '{print $2}' | sort -u | tr '\n' ' ')"
elif [ -n "$LATEST" ]; then
    PENULT="3.$(( ${LATEST#3.} - 1 ))"
    if [ "$BASE_IMAGE" = "alpine:$PENULT" ]; then
        pass T04 "base is the penultimate stable Alpine" "alpine:$PENULT (latest published is $LATEST) — checked live against Docker Hub"
    else
        fail T04 "base must be alpine:$PENULT (penultimate; latest is $LATEST)" "found: $BASE_IMAGE"
    fi
else
    block T04 "Docker Hub unreachable — cannot confirm $BASE_IMAGE is still penultimate" "re-run with network access before the defense"
fi

# T05 — our own Dockerfiles, built through compose by the Makefile
ok=1
for s in $SERVICES; do
    [ -f "srcs/requirements/$s/Dockerfile" ] || { ok=0; fail T05 "missing srcs/requirements/$s/Dockerfile"; }
    svc_block "$s" | grep -q 'build:' || { ok=0; fail T05 "service $s has no build: directive"; }
done
grep -q 'docker compose -f srcs/docker-compose.yml' Makefile || { ok=0; fail T05 "Makefile does not build through the compose file"; }
[ $ok -eq 1 ] && pass T05 "three hand-written Dockerfiles, built from compose, driven by the Makefile"

# T06 — never pull ready-made images (Alpine/Debian excluded)
FOREIGN=$(grep -h '^FROM' $DOCKERFILES | awk '{print $2}' | grep -vE '^(alpine|debian):' || true)
PULLED=$(grep -nE '^\s+image:' "$COMPOSE_FILE" | grep -vE 'image: *(nginx|wordpress|mariadb):inception' || true)
if [ -n "$FOREIGN" ]; then
    fail T06 "a Dockerfile builds on a non-Alpine/Debian image" "$FOREIGN"
elif [ -n "$PULLED" ]; then
    fail T06 "compose references an image that is not built here" "$PULLED"
else
    if [ $RUNNING -eq 1 ]; then
        ok=1
        for img in nginx:inception wordpress:inception mariadb:inception; do
            docker image history --no-trunc "$img" 2>/dev/null | grep -q 'entrypoint.sh' \
                || { ok=0; fail T06 "$img does not look like a local build of this repo"; }
        done
        [ $ok -eq 1 ] && pass T06 "no ready-made service image is pulled" "all bases are $BASE_IMAGE; all three running images carry this repo's entrypoint layer"
    else
        pass T06 "no ready-made service image is referenced" "all bases are $BASE_IMAGE (runtime provenance needs the stack up)"
    fi
fi

# ═════════════════════════════════════════════════════════════════════
section "The three service containers"
# ═════════════════════════════════════════════════════════════════════

# T07 — NGINX with TLSv1.2 / TLSv1.3 only
NGINX_CONF=srcs/requirements/nginx/conf/nginx.conf
SSLP=$(sed -n 's/^[[:space:]]*ssl_protocols[[:space:]]*//p' "$NGINX_CONF" | tr -d ';' | tr -s ' ')
case "$SSLP" in
    "TLSv1.2 TLSv1.3"|"TLSv1.3 TLSv1.2") static_tls=1 ;;
    *) static_tls=0 ;;
esac
if [ $static_tls -eq 0 ]; then
    fail T07 "ssl_protocols must be exactly 'TLSv1.2 TLSv1.3'" "found: ${SSLP:-none}"
elif [ "$PROBE_MODE" = "none" ]; then
    block T07 "declared TLSv1.2+TLSv1.3 only, but the handshake matrix needs the stack up" "start it with 'make up'"
else
    matrix=""; ok=1
    for v in tls1 tls1_1; do
        if probe "echo | openssl s_client -connect \$D:443 -servername \$D -$v 2>/dev/null | grep -qE 'Cipher is [A-Z]'"; then
            ok=0; matrix="$matrix $v=ACCEPTED"
        else
            matrix="$matrix $v=rejected"
        fi
    done
    for v in tls1_2 tls1_3; do
        if probe "echo | openssl s_client -connect \$D:443 -servername \$D -$v 2>/dev/null | grep -qE 'Cipher is [A-Z]'"; then
            matrix="$matrix $v=accepted"
        else
            ok=0; matrix="$matrix $v=FAILED"
        fi
    done
    if [ $ok -eq 1 ]; then
        pass T07 "nginx negotiates TLSv1.2/1.3 only" "handshake matrix:$matrix $(probe_note)"
    else
        fail T07 "TLS protocol enforcement is wrong" "handshake matrix:$matrix"
    fi
fi

# T08 — WordPress + php-fpm, installed and configured, without nginx
if [ $RUNNING -eq 1 ]; then
    ok=1; detail=""
    docker exec wordpress sh -c 'command -v php-fpm84' >/dev/null 2>&1 || { ok=0; fail T08 "php-fpm84 not installed in the wordpress container"; }
    docker exec wordpress sh -c 'command -v nginx' >/dev/null 2>&1 && { ok=0; fail T08 "nginx is present in the wordpress container"; }
    docker exec wordpress test -f /var/www/html/wp-config.php || { ok=0; fail T08 "wp-config.php missing — WordPress is not configured"; }
    WPV=$(docker exec wordpress wp --allow-root --path=/var/www/html core version 2>/dev/null)
    [ -n "$WPV" ] || { ok=0; fail T08 "WordPress core not installed"; }
    docker exec wordpress sh -c 'php-fpm84 -t' >/dev/null 2>&1 || { ok=0; fail T08 "php-fpm configuration does not validate"; }
    PHPV=$(docker exec wordpress php -r 'echo PHP_VERSION;' 2>/dev/null)
    detail="WordPress $WPV on php-fpm $PHPV, config valid, no nginx binary"
    [ $ok -eq 1 ] && pass T08 "wordpress container runs WordPress + php-fpm only" "$detail"
else
    block T08 "stack is down — start it with 'make up'"
fi

# T09 — MariaDB only, without nginx
if [ $RUNNING -eq 1 ]; then
    ok=1
    docker exec mariadb sh -c 'command -v mariadbd' >/dev/null 2>&1 || { ok=0; fail T09 "mariadbd not installed in the mariadb container"; }
    docker exec mariadb sh -c 'command -v nginx' >/dev/null 2>&1 && { ok=0; fail T09 "nginx is present in the mariadb container"; }
    docker exec mariadb sh -c 'command -v php-fpm84 || command -v php' >/dev/null 2>&1 && { ok=0; fail T09 "PHP is present in the mariadb container"; }
    DBV=$(docker exec mariadb sh -c 'MYSQL_PWD="$(cat /run/secrets/db_password)" mariadb -u "$MYSQL_USER" -N -e "SELECT VERSION();"' 2>/dev/null)
    [ -n "$DBV" ] || { ok=0; fail T09 "the application user cannot query MariaDB"; }
    [ $ok -eq 1 ] && pass T09 "mariadb container runs MariaDB only" "server $DBV, reachable as the application user; no nginx, no PHP"
else
    block T09 "stack is down — start it with 'make up'"
fi

# ═════════════════════════════════════════════════════════════════════
printf "\n${BLU}══ Summary ══${RST}  ${GRN}%d passed${RST}  ${RED}%d failed${RST}  ${YLW}%d blocked${RST}\n" \
    "$PASS" "$FAIL" "$BLOCK"
[ "$PROBE_MODE" = "network" ] && printf "${DIM}HTTPS checks ran from inside the docker network: this host cannot bind :443 (rootless Docker).${RST}\n"
[ $FAIL -gt 254 ] && exit 254
exit $FAIL
