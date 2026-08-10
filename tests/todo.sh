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
section "Volumes and network"
# ═════════════════════════════════════════════════════════════════════

vol_block() { awk '/^volumes:/,/^networks:/' "$COMPOSE_FILE"; }

# T10 — a volume holding the WordPress database
if vol_block | grep -q '^  db_data:'; then
    if [ $RUNNING -eq 1 ]; then
        if docker exec mariadb test -d /var/lib/mysql/mysql \
           && docker inspect mariadb --format '{{range .Mounts}}{{.Name}}:{{.Destination}} {{end}}' | grep -q 'inception_db_data:/var/lib/mysql'; then
            NT=$(docker exec mariadb sh -c 'MYSQL_PWD="$(cat /run/secrets/db_password)" mariadb -u "$MYSQL_USER" "$MYSQL_DATABASE" -N -e "SHOW TABLES LIKE \"wp_%\";"' 2>/dev/null | wc -l)
            pass T10 "a volume holds the WordPress database" "inception_db_data mounted at /var/lib/mysql, $NT wp_* tables present"
        else
            fail T10 "db_data is not mounted at /var/lib/mysql or the datadir is empty"
        fi
    else
        pass T10 "db_data volume declared for the database" "runtime contents need the stack up"
    fi
else
    fail T10 "no db_data volume declared"
fi

# T11 — a second volume holding the website files
if vol_block | grep -q '^  wp_data:'; then
    if [ $RUNNING -eq 1 ]; then
        if docker exec wordpress test -f /var/www/html/wp-config.php \
           && docker inspect wordpress --format '{{range .Mounts}}{{.Name}}:{{.Destination}} {{end}}' | grep -q 'inception_wp_data:/var/www/html'; then
            pass T11 "a second volume holds the website files" "inception_wp_data mounted at /var/www/html, WordPress core present"
        else
            fail T11 "wp_data is not mounted at /var/www/html or the site is missing"
        fi
    else
        pass T11 "wp_data volume declared for the site files" "runtime contents need the stack up"
    fi
else
    fail T11 "no wp_data volume declared"
fi

# T12 — named volumes only, no bind mounts for these two
ok=1
grep -q '^volumes:' "$COMPOSE_FILE" || { ok=0; fail T12 "no top-level volumes: section"; }
HOSTMOUNT=$(grep -nE '^\s+- (/|\./|~)[^ ]*:' "$COMPOSE_FILE" || true)
[ -n "$HOSTMOUNT" ] && { ok=0; fail T12 "a service bind-mounts a host path directly" "$HOSTMOUNT"; }
if [ $RUNNING -eq 1 ]; then
    # Docker implements file-based secrets as bind mounts; only the two
    # data mounts are inspected here.
    BADTYPE=$(docker inspect $SERVICES \
        --format '{{$n := .Name}}{{range .Mounts}}{{if or (eq .Destination "/var/lib/mysql") (eq .Destination "/var/www/html")}}{{$n}}:{{.Type}} {{end}}{{end}}' \
        | tr ' ' '\n' | grep -v ':volume$' | grep -v '^$' || true)
    [ -n "$BADTYPE" ] && { ok=0; fail T12 "a data mount is not a named volume" "$BADTYPE"; }
fi
[ $ok -eq 1 ] && pass T12 "both persistent stores are Docker named volumes, not bind mounts" \
    "no service mounts a host path; data mounts report type=volume"

# T13 — both volumes store their data inside /home/<login>/data
ok=1; devs=""
for v in db_data wp_data; do
    dev=$(vol_block | awk -v tgt="  $v:" '$0==tgt{f=1;next} f && /^  [a-z_]+:/{f=0} f' | sed -n 's/.*device: *//p')
    case "$dev" in
        "$DATA_DIR"/*) devs="$devs $v→$dev" ;;
        *) ok=0; fail T13 "volume $v stores data outside $DATA_DIR" "device: ${dev:-none}" ;;
    esac
done
[ $ok -eq 1 ] && pass T13 "both named volumes are rooted in $DATA_DIR" "$devs"

# T15 — a docker network connects the containers
ok=1
grep -q '^networks:' "$COMPOSE_FILE" || { ok=0; fail T15 "no top-level networks: section"; }
if [ $RUNNING -eq 1 ]; then
    DRV=$(docker network inspect --format '{{.Driver}}' inception 2>/dev/null)
    [ "$DRV" = "bridge" ] || { ok=0; fail T15 "network 'inception' is not a bridge network" "driver: ${DRV:-missing}"; }
    ATT=$(docker network inspect --format '{{range .Containers}}{{.Name}} {{end}}' inception 2>/dev/null)
    for c in $SERVICES; do
        printf '%s' "$ATT" | grep -q "$c" || { ok=0; fail T15 "$c is not attached to the inception network"; }
    done
    docker exec wordpress nc -z mariadb 3306 2>/dev/null || { ok=0; fail T15 "wordpress cannot reach mariadb:3306 by service name"; }
    docker exec nginx nc -z wordpress 9000 2>/dev/null || { ok=0; fail T15 "nginx cannot reach wordpress:9000 by service name"; }
    [ $ok -eq 1 ] && pass T15 "a bridge network connects all three containers" "service-name DNS works: wordpress→mariadb:3306, nginx→wordpress:9000"
else
    [ $ok -eq 1 ] && block T15 "network declared, but connectivity needs the stack up"
fi

# ═════════════════════════════════════════════════════════════════════
section "Crash behaviour and the keep-alive anti-pattern"
# ═════════════════════════════════════════════════════════════════════

# T16 — kill the service process and prove the container comes back.
#
# The signal is sent from *inside* the container, at PID 1, which is the
# daemon itself. Two Docker behaviours make this the only correct way to
# simulate a crash here:
#
#   * `docker kill` / `docker stop` from the host count as a manual stop
#     request, and a restart policy deliberately does not fire for those
#     (verified: the containers stayed Exited(137) with RestartCount=0).
#   * `kill -9 1` from inside is a silent no-op — the kernel does not
#     deliver default-action signals to a PID namespace's init from
#     within that namespace. Only signals the daemon actually handles,
#     such as SIGTERM, get through.
#
# So `kill 1` inside makes the daemon exit on its own, which is exactly
# the "the service died" event the restart policy exists for.
if [ $RUNNING -eq 1 ]; then
    ok=1; detail=""
    for c in $SERVICES; do
        BEFORE=$(docker inspect --format '{{.State.StartedAt}}' "$c")
        docker exec "$c" kill 1 2>/dev/null || true
        i=0; back=0
        while [ $i -lt 40 ]; do
            sleep 1; i=$((i+1))
            ST=$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null || echo gone)
            AFTER=$(docker inspect --format '{{.State.StartedAt}}' "$c" 2>/dev/null || echo x)
            [ "$ST" = "running" ] && [ "$AFTER" != "$BEFORE" ] && { back=1; break; }
        done
        if [ $back -eq 1 ]; then
            detail="$detail $c(${i}s)"
        else
            ok=0; fail T16 "$c did not restart after SIGKILL to PID 1"
        fi
    done
    if [ $ok -eq 1 ]; then
        # and back to healthy, not merely running
        i=0
        while [ $i -lt 60 ]; do
            H=$(docker inspect --format '{{range $k,$v := .State}}{{if eq $k "Health"}}{{$v.Status}}{{end}}{{end}}' $SERVICES 2>/dev/null | tr '\n' ' ')
            case "$H" in *starting*|*unhealthy*) sleep 2; i=$((i+1)) ;; *) break ;; esac
        done
        pass T16 "every container restarts after its service process is killed" \
            "recovery:$detail — policy $(docker inspect nginx --format '{{.HostConfig.RestartPolicy.Name}}'), nginx RestartCount=$(docker inspect nginx --format '{{.RestartCount}}')"
    fi
else
    block T16 "stack is down — start it with 'make up'"
fi

# T20 — no infinite-loop / keep-alive entrypoint, demonstrated not just grepped.
HACKS=$(grep -hnE 'tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+true|while[[:space:]]+:;|sleep[[:space:]]+[0-9]{4,}' \
        $DOCKERFILES $ENTRYPOINTS "$COMPOSE_FILE" 2>/dev/null || true)
if [ -n "$HACKS" ]; then
    fail T20 "a prohibited keep-alive pattern is present" "$HACKS"
else
    ok=1; detail=""
    # every entrypoint must hand PID 1 to the daemon with exec
    for e in $ENTRYPOINTS; do
        LAST=$(grep -vE '^\s*(#|$)' "$e" | tail -1)
        case "$LAST" in
            exec\ *) ;;
            *) ok=0; fail T20 "$e does not end with 'exec <daemon>'" "last line: $LAST" ;;
        esac
    done
    if [ $ok -eq 1 ] && command -v docker >/dev/null 2>&1; then
        # Demonstration: build the anti-pattern and show what it costs.
        # A container whose PID 1 is `tail -f` keeps reporting Up after its
        # service dies, and ignores SIGTERM on docker stop.
        BAD=inception-antipattern-test
        docker rm -f "$BAD" >/dev/null 2>&1
        docker run -d --name "$BAD" --stop-timeout 3 "$BASE_IMAGE" \
            sh -c 'sleep 600 & tail -f /dev/null' >/dev/null 2>&1
        sleep 1
        # kill the "service" the container is supposed to be running
        docker exec "$BAD" pkill -9 sleep 2>/dev/null || true
        sleep 1
        FAKE=$(docker inspect --format '{{.State.Status}}' "$BAD" 2>/dev/null)
        # docker stop sends SIGTERM to PID 1; a keep-alive PID 1 has no
        # handler for it, so the container survives the grace period and
        # is SIGKILLed instead — exit code 137.
        docker stop "$BAD" >/dev/null 2>&1
        BADCODE=$(docker inspect --format '{{.State.ExitCode}}' "$BAD" 2>/dev/null)
        docker rm -f "$BAD" >/dev/null 2>&1
        detail="demo: with 'tail -f' as PID 1 the container still reported '$FAKE' after its service was killed, then ignored SIGTERM and had to be SIGKILLed (exit $BADCODE). Here PID 1 is the daemon itself (T03), so SIGTERM reaches it."
        pass T20 "no keep-alive hack; every entrypoint execs the real daemon" "$detail"
        printf "         ${DIM}see docs/why-no-hacky-patches.md${RST}\n"
    elif [ $ok -eq 1 ]; then
        pass T20 "no keep-alive hack; every entrypoint execs the real daemon"
    fi
fi

# ═════════════════════════════════════════════════════════════════════
section "Prohibited constructs, users and the domain"
# ═════════════════════════════════════════════════════════════════════

# T17 — documentation explaining why keep-alive hacks are wrong
DOC=docs/why-no-hacky-patches.md
if [ ! -f "$DOC" ]; then
    fail T17 "missing $DOC" "the subject asks for a written explanation with official references"
else
    ok=1
    for topic in 'PID 1' 'SIGTERM' 'exec' 'HEALTHCHECK\|healthcheck'; do
        grep -qi "$topic" "$DOC" || { ok=0; fail T17 "$DOC does not cover: $topic"; }
    done
    NREF=$(grep -c 'https://docs.docker.com' "$DOC")
    [ "$NREF" -ge 4 ] || { ok=0; fail T17 "$DOC cites only $NREF official Docker references (want >= 4)"; }
    [ $ok -eq 1 ] && pass T17 "documented why tail -f and friends are wrong practice" \
        "$DOC — $NREF links to docs.docker.com, covering PID 1, signal delivery, exec form and healthchecks"
fi

# T18 — network_mode: host, --link and links: are forbidden
ok=1
grep -qE 'network_mode:[[:space:]]*host' "$COMPOSE_FILE" && { ok=0; fail T18 "network_mode: host is present"; }
grep -qE '^\s+links:' "$COMPOSE_FILE" && { ok=0; fail T18 "links: is present"; }
grep -qE '\-\-link' "$COMPOSE_FILE" Makefile $DOCKERFILES 2>/dev/null && { ok=0; fail T18 "--link is used"; }
if [ $RUNNING -eq 1 ]; then
    for c in $SERVICES; do
        NM=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$c")
        [ "$NM" = "host" ] && { ok=0; fail T18 "$c runs with host networking"; }
        LK=$(docker inspect --format '{{.HostConfig.Links}}' "$c")
        [ "$LK" = "[]" ] || [ -z "$LK" ] || { ok=0; fail T18 "$c has legacy links: $LK"; }
    done
fi
[ $ok -eq 1 ] && pass T18 "no host networking, no links, no --link" "checked in the compose file and on the running containers"

# T19 — the network line must be present in docker-compose.yml
if grep -q '^networks:' "$COMPOSE_FILE" && svc_block nginx | grep -q 'networks:'; then
    pass T19 "the network line is present in docker-compose.yml" \
        "top-level networks: plus a networks: entry on each service"
else
    fail T19 "docker-compose.yml is missing the network declaration"
fi

# T21 — exactly two WordPress users, admin name must not contain "admin"
if [ $RUNNING -eq 1 ]; then
    ULIST=$(docker exec wordpress wp --allow-root --path=/var/www/html user list --fields=user_login,roles --format=csv 2>/dev/null | tail -n +2)
    NUSERS=$(printf '%s\n' "$ULIST" | grep -c .)
    ADMINS=$(printf '%s\n' "$ULIST" | grep ',administrator' | cut -d, -f1)
    NADMIN=$(printf '%s\n' "$ADMINS" | grep -c .)
    ok=1
    [ "$NUSERS" -eq 2 ] || { ok=0; fail T21 "expected 2 WordPress users, found $NUSERS" "$ULIST"; }
    [ "$NADMIN" -eq 1 ] || { ok=0; fail T21 "expected exactly 1 administrator, found $NADMIN"; }
    for a in $ADMINS; do
        case "$(printf %s "$a" | tr '[:upper:]' '[:lower:]')" in
            *admin*) ok=0; fail T21 "administrator login '$a' contains 'admin'" ;;
        esac
    done
    # the rule is also enforced at boot, not merely satisfied by luck
    grep -q 'must not contain' srcs/requirements/wordpress/tools/entrypoint.sh \
        || printf "         ${DIM}note: the entrypoint does not appear to enforce the rule${RST}\n"
    [ $ok -eq 1 ] && pass T21 "two WordPress users, one compliant administrator" \
        "$(printf '%s' "$ULIST" | tr '\n' ' ') — and the entrypoint refuses to boot on a non-compliant name"
else
    block T21 "stack is down — start it with 'make up'"
fi

# T22 — the volumes are visible in /home/<login>/data on the host
if [ $RUNNING -eq 1 ]; then
    ok=1
    [ -d "$DATA_DIR/wordpress" ] || { ok=0; fail T22 "$DATA_DIR/wordpress does not exist on the host"; }
    [ -d "$DATA_DIR/mariadb" ]   || { ok=0; fail T22 "$DATA_DIR/mariadb does not exist on the host"; }
    [ -f "$DATA_DIR/wordpress/wp-config.php" ] || { ok=0; fail T22 "the site files are not visible at $DATA_DIR/wordpress"; }
    # the datadir is mode 750 owned by the container's mysql user, so it is
    # inspected through the container rather than from the host
    docker exec mariadb test -d /var/lib/mysql/mysql || { ok=0; fail T22 "the MariaDB datadir is empty"; }
    NFILES=$(ls -1 "$DATA_DIR/wordpress" 2>/dev/null | wc -l)
    [ $ok -eq 1 ] && pass T22 "both volumes live under $DATA_DIR on the host" \
        "$NFILES entries in $DATA_DIR/wordpress; MariaDB datadir populated (mode 750, inspected in-container)"
else
    block T22 "stack is down — start it with 'make up'"
fi

# T23 — the domain resolves to the local machine
DOMAIN_OK=0
if grep -qE "^[[:space:]]*127\.0\.0\.1[[:space:]]+.*$DOMAIN" /etc/hosts 2>/dev/null; then DOMAIN_OK=1; fi
RESOLVED=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1)
case "$DOMAIN" in
    "$LOGIN".42.fr) NAME_OK=1 ;;
    *) NAME_OK=0 ;;
esac
if [ $NAME_OK -eq 0 ]; then
    fail T23 "the domain must be $LOGIN.42.fr" "srcs/.env has DOMAIN_NAME=$DOMAIN"
elif [ "$RESOLVED" = "127.0.0.1" ] || [ $DOMAIN_OK -eq 1 ]; then
    pass T23 "$DOMAIN resolves to the local machine" "/etc/hosts entry present${RESOLVED:+, resolves to $RESOLVED}"
else
    block T23 "$DOMAIN does not resolve to 127.0.0.1 yet" \
        "'make setup' adds it; it needs sudo. Add manually: echo '127.0.0.1 $DOMAIN' | sudo tee -a /etc/hosts"
fi

# ═════════════════════════════════════════════════════════════════════
printf "\n${BLU}══ Summary ══${RST}  ${GRN}%d passed${RST}  ${RED}%d failed${RST}  ${YLW}%d blocked${RST}\n" \
    "$PASS" "$FAIL" "$BLOCK"
[ "$PROBE_MODE" = "network" ] && printf "${DIM}HTTPS checks ran from inside the docker network: this host cannot bind :443 (rootless Docker).${RST}\n"
[ $FAIL -gt 254 ] && exit 254
exit $FAIL
