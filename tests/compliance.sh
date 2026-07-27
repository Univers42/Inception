#!/bin/sh
# ═════════════════════════════════════════════════════════════════════
#  Inception — subject v5.2 compliance test suite
#
#  Usage:  sh tests/compliance.sh [--deep]
#
#  [S] static checks   — repo/config audit, always run
#  [R] runtime checks  — need the stack up (skipped otherwise)
#  [D] deep checks     — --deep only: crash-restart & persistence
#                        (restarts containers, cycles the stack)
#
#  Exit code = number of failed checks. No sudo required.
# ═════════════════════════════════════════════════════════════════════
set -u

cd "$(dirname "$0")/.." || exit 1

DEEP=0
[ "${1:-}" = "--deep" ] && DEEP=1

if [ -t 1 ]; then
    RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
    BLU='\033[1;34m'; DIM='\033[2m'; RST='\033[0m'
else
    RED=''; GRN=''; YLW=''; BLU=''; DIM=''; RST=''
fi

PASS=0; FAIL=0; WARN=0; SKIP=0
pass() { PASS=$((PASS+1)); printf "  ${GRN}✔${RST} %s\n" "$1"; }
fail() { FAIL=$((FAIL+1)); printf "  ${RED}✘${RST} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${DIM}%s${RST}\n" "$2"; }
warn() { WARN=$((WARN+1)); printf "  ${YLW}▲${RST} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${DIM}%s${RST}\n" "$2"; }
skip() { SKIP=$((SKIP+1)); printf "  ${DIM}– %s (skipped)${RST}\n" "$1"; }
section() { printf "\n${BLU}%s${RST}\n" "$1"; }

LOGIN=$(sed -n 's/^LOGIN[[:space:]]*=[[:space:]]*//p' Makefile | head -1)
[ -n "$LOGIN" ] || LOGIN=$(whoami)
DOMAIN=$(sed -n 's/^DOMAIN_NAME=//p' srcs/.env 2>/dev/null | head -1)
[ -n "$DOMAIN" ] || DOMAIN="$LOGIN.42.fr"
COMPOSE_FILE=srcs/docker-compose.yml
DOCKERFILES="srcs/requirements/nginx/Dockerfile srcs/requirements/wordpress/Dockerfile srcs/requirements/mariadb/Dockerfile"
ENTRYPOINTS="srcs/requirements/nginx/tools/entrypoint.sh srcs/requirements/wordpress/tools/entrypoint.sh srcs/requirements/mariadb/tools/entrypoint.sh"

printf "${BLU}══ Inception compliance suite ══${RST}  login=%s domain=%s\n" "$LOGIN" "$DOMAIN"

# ─────────────────────────────────────────────────────────────────────
section "[S] Structure & Makefile"
# ─────────────────────────────────────────────────────────────────────

# S01 required layout
ok=1
for f in Makefile "$COMPOSE_FILE" srcs/.env \
         secrets/db_password.txt secrets/db_root_password.txt secrets/credentials.txt; do
    [ -f "$f" ] || { ok=0; fail "S01 missing: $f"; }
done
for s in nginx wordpress mariadb; do
    [ -f "srcs/requirements/$s/Dockerfile" ]         || { ok=0; fail "S01 missing Dockerfile for $s"; }
    [ -f "srcs/requirements/$s/tools/entrypoint.sh" ] || { ok=0; fail "S01 missing entrypoint for $s"; }
done
[ $ok -eq 1 ] && pass "S01 required layout (Makefile, srcs/, secrets/, one Dockerfile per service)"

# S02 documentation required by subject
ok=1
for f in README.md USER_DOC.md DEV_DOC.md; do
    [ -f "$f" ] || { ok=0; fail "S02 missing: $f"; }
done
if [ -f README.md ]; then
    head -1 README.md | grep -q '^\*This project has been created as part of the 42 curriculum by .*\*$' \
        || { ok=0; fail "S02 README first line must be the italicised 42-curriculum sentence"; }
fi
[ $ok -eq 1 ] && pass "S02 README.md + USER_DOC.md + DEV_DOC.md present, README header compliant"

# S03 penultimate stable Alpine
BASES=$(grep -h '^FROM' $DOCKERFILES | awk '{print $2}' | sort -u)
NBASE=$(printf '%s\n' "$BASES" | wc -l)
LATEST=$(curl -fsS --max-time 8 "https://hub.docker.com/v2/repositories/library/alpine/tags?page_size=100&name=3." 2>/dev/null \
         | tr ',' '\n' | sed -n 's/.*"name":"\(3\.[0-9][0-9]*\)".*/\1/p' | sort -t. -k2 -n | uniq | tail -1)
if [ "$NBASE" != "1" ]; then
    fail "S03 all Dockerfiles must share one pinned base" "$(printf '%s' "$BASES" | tr '\n' ' ')"
elif [ -n "$LATEST" ]; then
    PENULT="3.$(( ${LATEST#3.} - 1 ))"
    if [ "$BASES" = "alpine:$PENULT" ]; then
        pass "S03 base is penultimate stable Alpine (alpine:$PENULT; latest is $LATEST)"
    else
        fail "S03 base must be alpine:$PENULT (penultimate; latest is $LATEST)" "found: $BASES"
    fi
else
    case "$BASES" in
        alpine:3.[0-9]*) warn "S03 base is pinned ($BASES) but Docker Hub unreachable — verify it is still the penultimate stable" ;;
        *) fail "S03 base must be a pinned Alpine or Debian version" "found: $BASES" ;;
    esac
fi

# S04 latest tag prohibited
if grep -hnE '(^FROM.*:latest|image:.*:latest)' $DOCKERFILES "$COMPOSE_FILE" | grep -q .; then
    fail "S04 ':latest' tag found" "$(grep -hnE '(^FROM.*:latest|image:.*:latest)' $DOCKERFILES "$COMPOSE_FILE")"
else
    pass "S04 no ':latest' tag anywhere"
fi

# helper: print the compose block of one service (2-space indented key)
svc_block() {
    awk -v tgt="  $1:" '$0==tgt{f=1;next} f && /^  [a-zA-Z0-9_-]+:[[:space:]]*$/{f=0} f' "$COMPOSE_FILE"
}

# S05 every service is built locally (no ready-made images pulled)
ok=1
for s in nginx wordpress mariadb; do
    svc_block "$s" | grep -q 'build:' || { ok=0; fail "S05 service $s has no build: directive"; }
done
FROMS=$(grep -h '^FROM' $DOCKERFILES | awk '{print $2}' | grep -vE '^(alpine|debian):' || true)
[ -n "$FROMS" ] && { ok=0; fail "S05 non-Alpine/Debian base image" "$FROMS"; }
[ $ok -eq 1 ] && pass "S05 all services built from local Dockerfiles, bases restricted to Alpine/Debian"

# S06 prohibited keep-alive hacks
HACKS=$(grep -hnE 'tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+true|while[[:space:]]+:;|sleep[[:space:]]+[0-9]{4,}' \
        $DOCKERFILES $ENTRYPOINTS "$COMPOSE_FILE" 2>/dev/null || true)
if [ -n "$HACKS" ]; then
    fail "S06 prohibited hacky patch found (tail -f / sleep infinity / while true)" "$HACKS"
else
    pass "S06 no prohibited keep-alive hacks (tail -f, sleep infinity, while true, bash loops)"
fi

# S07 network rules
ok=1
grep -q '^networks:' "$COMPOSE_FILE" || { ok=0; fail "S07 top-level 'networks:' line missing"; }
grep -qE 'network_mode:[[:space:]]*host' "$COMPOSE_FILE" && { ok=0; fail "S07 network_mode: host is forbidden"; }
grep -qE '^\s+links:' "$COMPOSE_FILE" && { ok=0; fail "S07 links: is forbidden"; }
[ $ok -eq 1 ] && pass "S07 network line present; no host networking; no links:"

# S08 restart policy on every service
N=$(grep -c 'restart:' "$COMPOSE_FILE")
if [ "$N" -ge 3 ]; then
    pass "S08 restart policy declared for all 3 services ($(grep 'restart:' "$COMPOSE_FILE" | awk '{print $2}' | sort -u | tr '\n' ' '))"
else
    fail "S08 restart policy missing on some services (found $N of 3)"
fi

# S09 image name == service name
ok=1
for s in nginx wordpress mariadb; do
    svc_block "$s" | grep -q "image: *$s:" || { ok=0; fail "S09 image name for service '$s' must be '$s:<tag>'"; }
done
[ $ok -eq 1 ] && pass "S09 each image is named after its service (nginx, wordpress, mariadb)"

# S10 only nginx publishes ports, and only 443
PORTS=$(grep -A1 'ports:' "$COMPOSE_FILE" | grep -E '^\s+-' | tr -d ' "-' || true)
if [ "$PORTS" = "443:443" ]; then
    pass "S10 single published port: 443 (nginx)"
else
    fail "S10 published ports must be exactly 443:443 on nginx" "found: $PORTS"
fi

# S11 two named volumes rooted in /home/<login>/data, no service-level bind mounts
ok=1
for v in db_data wp_data; do
    awk "/^volumes:/,/^networks:/" "$COMPOSE_FILE" | grep -q "  $v:" || { ok=0; fail "S11 named volume '$v' missing"; }
done
DEVS=$(awk '/^volumes:/,/^networks:/' "$COMPOSE_FILE" | sed -n 's/.*device: *//p')
for d in $DEVS; do
    case "$d" in
        /home/$LOGIN/data/*) : ;;
        *) ok=0; fail "S11 volume device outside /home/$LOGIN/data" "$d" ;;
    esac
done
if grep -E '^\s+- (/|\.|~)[^ ]*:' "$COMPOSE_FILE" | grep -vq 'device:'; then
    ok=0; fail "S11 service-level host-path bind mount found (named volumes required)"
fi
[ $ok -eq 1 ] && pass "S11 two named volumes stored under /home/$LOGIN/data, no service bind mounts"

# S12 secrets configured, git-ignored, never tracked
ok=1
grep -q '^secrets:' "$COMPOSE_FILE" || { ok=0; fail "S12 no top-level secrets: in compose"; }
for pat in secrets srcs/.env; do
    git check-ignore -q "$pat" 2>/dev/null || git check-ignore -q "$pat/x" 2>/dev/null \
        || { ok=0; fail "S12 '$pat' is not git-ignored"; }
done
TRACKED=$(git ls-files | grep -E '(^|/)secrets/|srcs/\.env$|\.(key|crt|pem)$' || true)
[ -n "$TRACKED" ] && { ok=0; fail "S12 sensitive files are tracked by git" "$TRACKED"; }
grep -q 'ca_key' "$COMPOSE_FILE" && { ok=0; fail "S12 CA private key must never be mounted into a container"; }
[ $ok -eq 1 ] && pass "S12 Docker secrets configured; secrets/ and srcs/.env ignored and untracked; CA key stays on host"

# S13 no passwords in Dockerfiles
if grep -hinE 'pass(word)?[[:space:]]*=|ENV.*PASS' $DOCKERFILES | grep -vq '^$'; then
    fail "S13 password-like content in a Dockerfile" "$(grep -hinE 'pass(word)?[[:space:]]*=|ENV.*PASS' $DOCKERFILES)"
else
    pass "S13 no passwords in Dockerfiles"
fi

# S14 no plaintext credentials in tracked files
LEAKS=$(git ls-files -z | xargs -0 grep -inE "(password|passwd|secret|api_key|token)[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9@#%!]{4,}" 2>/dev/null \
        | grep -viE '\$|\{\{|/run/secrets|secrets/|password\.txt|openssl rand|sql_escape|MYSQL_PWD|_FILE|example|placeholder|YourDb|WpAdmin|WpEditor' || true)
if [ -n "$LEAKS" ]; then
    fail "S14 possible plaintext credential in tracked files" "$LEAKS"
else
    pass "S14 no plaintext credentials in tracked files"
fi

# S15 no credentials anywhere in git history (subject: instant project failure)
HLEAKS=$(git log --all -p -- . 2>/dev/null \
         | grep -iE '^\+.*(password|passwd|secret)[[:space:]]*[:=][[:space:]]*['\''"]?[A-Za-z0-9@#%!]{4,}' \
         | grep -viE '\$|\{|/run/secrets|secrets/|password\.txt|openssl rand|sql_escape|MYSQL_PWD|_FILE|example|placeholder|YourDb|WpAdmin|WpEditor|IDENTIFIED BY' \
         | sort -u | head -5 || true)
if [ -n "$HLEAKS" ]; then
    fail "S15 credential-like lines exist in git HISTORY (rewrite history before submission!)" "$HLEAKS"
else
    pass "S15 git history clean of credential-like content"
fi

# S16 mandatory env usage
ok=1
grep -q "^DOMAIN_NAME=$DOMAIN" srcs/.env || { ok=0; fail "S16 srcs/.env must define DOMAIN_NAME=$DOMAIN"; }
grep -q '\${DOMAIN_NAME}' "$COMPOSE_FILE" || { ok=0; fail "S16 compose must consume env vars (\${DOMAIN_NAME})"; }
[ $ok -eq 1 ] && pass "S16 .env file present and consumed through compose interpolation"

# S17 admin username rule
WPADMIN=$(sed -n 's/^WP_ADMIN_USER=//p' srcs/.env | head -1)
case "$(printf %s "$WPADMIN" | tr '[:upper:]' '[:lower:]')" in
    *admin*) fail "S17 WP_ADMIN_USER '$WPADMIN' contains 'admin' (forbidden)" ;;
    "")      fail "S17 WP_ADMIN_USER not set in srcs/.env" ;;
    *)       pass "S17 WP admin username '$WPADMIN' complies with the naming rule" ;;
esac

# S18 entrypoints hand PID 1 to the daemon via exec
ok=1
for e in $ENTRYPOINTS; do
    LAST=$(grep -vE '^\s*(#|$)' "$e" | tail -1)
    case "$LAST" in
        exec\ *) : ;;
        *) ok=0; fail "S18 $e does not end with 'exec <daemon>'" "last line: $LAST" ;;
    esac
done
[ $ok -eq 1 ] && pass "S18 every entrypoint ends with exec — daemon runs as PID 1"

# S19 Makefile drives docker compose with the srcs compose file
if grep -q 'docker compose -f srcs/docker-compose.yml' Makefile; then
    pass "S19 Makefile builds/starts the stack through srcs/docker-compose.yml"
else
    fail "S19 Makefile must call docker compose with srcs/docker-compose.yml"
fi

# S20 domain resolves locally
if grep -qE "127\.0\.0\.1[[:space:]]+.*$DOMAIN" /etc/hosts 2>/dev/null; then
    pass "S20 $DOMAIN points to 127.0.0.1 in /etc/hosts"
else
    warn "S20 $DOMAIN not found in /etc/hosts (make setup adds it)"
fi

# S21 TLS material issued on host
ok=1
[ -f secrets/ca.crt ]     || { ok=0; warn "S21 secrets/ca.crt missing (run make setup)"; }
[ -f secrets/server.crt ] || { ok=0; warn "S21 secrets/server.crt missing (run make setup)"; }
if [ $ok -eq 1 ]; then
    if openssl x509 -in secrets/server.crt -noout -text | grep -q "DNS:$DOMAIN"; then
        pass "S21 server certificate exists with SAN $DOMAIN, signed on the host"
    else
        fail "S21 server certificate SAN does not include $DOMAIN"
    fi
fi

# ─────────────────────────────────────────────────────────────────────
section "[R] Runtime"
# ─────────────────────────────────────────────────────────────────────

RUNNING=1
for c in nginx wordpress mariadb; do
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$c" || RUNNING=0
done

if [ $RUNNING -eq 0 ]; then
    skip "R** stack not running — start it with 'make up' to run runtime checks"
else
    # R01 all containers healthy (wait for pending healthchecks)
    ok=1
    for c in nginx wordpress mariadb; do
        i=0
        while [ $i -lt 30 ]; do
            H=$(docker inspect --format '{{.State.Health.Status}}' "$c" 2>/dev/null || echo none)
            [ "$H" = "healthy" ] && break
            [ "$H" = "none" ] && break
            sleep 2; i=$((i+1))
        done
        S=$(docker inspect --format '{{.State.Status}}' "$c")
        H=$(docker inspect --format '{{.State.Health.Status}}' "$c" 2>/dev/null || echo none)
        if [ "$S" != "running" ] || { [ "$H" != "healthy" ] && [ "$H" != "none" ]; }; then
            ok=0; fail "R01 $c is $S/$H"
        fi
    done
    [ $ok -eq 1 ] && pass "R01 nginx, wordpress and mariadb all running and healthy"

    # R02 only 443 published
    PUB=$(docker ps --format '{{.Names}} {{.Ports}}' | grep -E '^(nginx|wordpress|mariadb) ' | grep -oE '0\.0\.0\.0:[0-9]+|\[::\]:[0-9]+' | grep -oE '[0-9]+$' | sort -u)
    if [ "$PUB" = "443" ]; then
        pass "R02 port 443 is the only published port"
    else
        fail "R02 published ports must be exactly {443}" "found: $(printf '%s' "$PUB" | tr '\n' ' ')"
    fi

    # R03 TLS protocol enforcement
    ok=1
    for v in tls1 tls1_1; do
        if echo | openssl s_client -connect "$DOMAIN:443" -$v 2>/dev/null | grep -qE 'Cipher is [A-Z]'; then
            ok=0; fail "R03 $v handshake unexpectedly succeeded"
        fi
    done
    for v in tls1_2 tls1_3; do
        if ! echo | openssl s_client -connect "$DOMAIN:443" -$v 2>/dev/null | grep -qE 'Cipher is [A-Z]'; then
            ok=0; fail "R03 $v handshake failed"
        fi
    done
    [ $ok -eq 1 ] && pass "R03 TLSv1.2 + TLSv1.3 accepted; TLSv1.0/1.1 rejected"

    # R04 certificate identity
    CERT=$(echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -subject -issuer 2>/dev/null)
    if printf '%s' "$CERT" | grep -q "CN *= *$DOMAIN" && printf '%s' "$CERT" | grep -q "Inception Local CA"; then
        pass "R04 served certificate is CN=$DOMAIN signed by the local CA"
    else
        fail "R04 unexpected certificate" "$CERT"
    fi

    # R05 WordPress is served
    BODY=$(curl -ks --max-time 10 "https://$DOMAIN/")
    SIZE=${#BODY}
    if [ "$SIZE" -gt 10000 ] && printf '%s' "$BODY" | grep -q 'wp-\(content\|includes\)'; then
        pass "R05 https://$DOMAIN serves a real WordPress page ($SIZE bytes)"
    else
        fail "R05 front page missing or empty ($SIZE bytes)"
    fi

    # R06 admin panel reachable
    CODE=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 10 "https://$DOMAIN/wp-login.php")
    if [ "$CODE" = "200" ]; then
        pass "R06 admin login page reachable (wp-login.php → 200)"
    else
        fail "R06 wp-login.php returned $CODE"
    fi

    # R07 no plain-HTTP entrypoint on port 80
    if curl -s -o /dev/null --max-time 3 "http://$DOMAIN/" 2>/dev/null; then
        fail "R07 port 80 answered — NGINX:443 must be the only entrypoint"
    else
        pass "R07 port 80 closed (connection refused)"
    fi

    # R08 WordPress users: two users, one compliant administrator
    ULIST=$(docker exec wordpress wp --allow-root --path=/var/www/html user list --fields=user_login,roles --format=csv 2>/dev/null | tail -n +2)
    NUSERS=$(printf '%s\n' "$ULIST" | grep -c .)
    NADMIN=$(printf '%s\n' "$ULIST" | grep -c ',administrator')
    ADMIN_LOGIN=$(printf '%s\n' "$ULIST" | grep ',administrator' | cut -d, -f1)
    ok=1
    [ "$NUSERS" -eq 2 ] || { ok=0; fail "R08 expected 2 WordPress users, found $NUSERS"; }
    [ "$NADMIN" -eq 1 ] || { ok=0; fail "R08 expected exactly 1 administrator, found $NADMIN"; }
    case "$(printf %s "$ADMIN_LOGIN" | tr '[:upper:]' '[:lower:]')" in
        *admin*|"") ok=0; fail "R08 administrator login '$ADMIN_LOGIN' violates naming rule" ;;
    esac
    [ $ok -eq 1 ] && pass "R08 two WP users; administrator '$ADMIN_LOGIN' complies with naming rule"

    # R09 an active theme exists (blank-site regression check)
    if docker exec wordpress wp --allow-root --path=/var/www/html theme list --status=active --field=name 2>/dev/null | grep -q .; then
        pass "R09 an active WordPress theme is installed"
    else
        fail "R09 no active theme — the site would render a blank page"
    fi

    # R10 real daemons run as PID 1
    ok=1
    for pair in "nginx:nginx" "wordpress:php-fpm84" "mariadb:mariadbd"; do
        c=${pair%%:*}; d=${pair#*:}
        P1=$(docker exec "$c" ps -o pid,comm 2>/dev/null | awk '$1==1{print $2}')
        [ "$P1" = "$d" ] || { ok=0; fail "R10 $c PID 1 is '$P1' (expected $d)"; }
    done
    [ $ok -eq 1 ] && pass "R10 PID 1 is the service daemon in every container (nginx, php-fpm84, mariadbd)"

    # R11 one service per container
    ok=1
    docker exec wordpress sh -c 'command -v nginx' >/dev/null 2>&1 && { ok=0; fail "R11 nginx binary present in wordpress container"; }
    docker exec mariadb  sh -c 'command -v nginx' >/dev/null 2>&1 && { ok=0; fail "R11 nginx binary present in mariadb container"; }
    docker exec nginx    sh -c 'command -v php-fpm84 || command -v mariadbd' >/dev/null 2>&1 && { ok=0; fail "R11 app daemons present in nginx container"; }
    [ $ok -eq 1 ] && pass "R11 strict service isolation (wordpress & mariadb ship no nginx, nginx ships no app daemons)"

    # R12 dedicated bridge network connects the three containers
    NETOK=1
    docker network inspect inception >/dev/null 2>&1 || NETOK=0
    if [ $NETOK -eq 1 ]; then
        DRV=$(docker network inspect --format '{{.Driver}}' inception)
        ATT=$(docker network inspect --format '{{range .Containers}}{{.Name}} {{end}}' inception)
        for c in nginx wordpress mariadb; do
            printf '%s' "$ATT" | grep -q "$c" || NETOK=0
        done
        [ "$DRV" = "bridge" ] || NETOK=0
    fi
    for c in nginx wordpress mariadb; do
        [ "$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$c")" = "host" ] && NETOK=0
    done
    if [ $NETOK -eq 1 ]; then
        pass "R12 bridge network 'inception' connects all three containers (no host networking)"
    else
        fail "R12 docker network misconfigured"
    fi

    # R13 named volumes bound to /home/<login>/data
    ok=1
    for pair in "inception_db_data:/home/$LOGIN/data/mariadb" "inception_wp_data:/home/$LOGIN/data/wordpress"; do
        v=${pair%%:*}; d=${pair#*:}
        DEV=$(docker volume inspect --format '{{index .Options "device"}}' "$v" 2>/dev/null)
        [ "$DEV" = "$d" ] || { ok=0; fail "R13 volume $v device is '$DEV' (expected $d)"; }
    done
    [ -f "/home/$LOGIN/data/wordpress/wp-config.php" ] || { ok=0; fail "R13 WordPress files not visible in /home/$LOGIN/data/wordpress"; }
    # the mariadb datadir is mode 750 (mysql-owned) — verify through the volume mount
    [ -d "/home/$LOGIN/data/mariadb" ] || { ok=0; fail "R13 /home/$LOGIN/data/mariadb missing on host"; }
    docker exec mariadb test -d /var/lib/mysql/mysql || { ok=0; fail "R13 MariaDB datadir empty in db_data volume"; }
    [ $ok -eq 1 ] && pass "R13 named volumes persist site + DB under /home/$LOGIN/data"

    # R14 secrets mounted; no password-like env vars leaked
    ok=1
    docker exec mariadb   test -f /run/secrets/db_root_password || { ok=0; fail "R14 db_root_password secret missing in mariadb"; }
    docker exec wordpress test -f /run/secrets/credentials      || { ok=0; fail "R14 credentials secret missing in wordpress"; }
    docker exec nginx     test -f /run/secrets/server_key       || { ok=0; fail "R14 server_key secret missing in nginx"; }
    ENVLEAK=$(docker inspect nginx wordpress mariadb --format '{{.Name}} {{.Config.Env}}' | grep -iE 'PASS|SECRET|TOKEN' || true)
    [ -n "$ENVLEAK" ] && { ok=0; fail "R14 password-like environment variable exposed" "$ENVLEAK"; }
    [ $ok -eq 1 ] && pass "R14 credentials delivered via Docker secrets only — none in container env"

    # R15 restart policy active on all containers
    POL=$(docker inspect nginx wordpress mariadb --format '{{.HostConfig.RestartPolicy.Name}}' | sort -u)
    if [ "$POL" = "unless-stopped" ] || [ "$POL" = "on-failure" ] || [ "$POL" = "always" ]; then
        pass "R15 restart policy '$POL' active on all containers"
    else
        fail "R15 inconsistent/missing restart policy" "$POL"
    fi

    # R16 database really holds the WordPress schema
    NT=$(docker exec mariadb sh -c 'MYSQL_PWD="$(cat /run/secrets/db_password)" mariadb -u "$MYSQL_USER" "$MYSQL_DATABASE" -N -e "SHOW TABLES LIKE \"wp_%\";"' 2>/dev/null | wc -l)
    if [ "$NT" -ge 10 ]; then
        pass "R16 WordPress schema present in MariaDB ($NT wp_* tables)"
    else
        fail "R16 WordPress tables missing (found $NT)"
    fi

    # R17 images built locally, not pulled (our COPY entrypoint layer is present)
    ok=1
    for img in nginx:inception wordpress:inception mariadb:inception; do
        docker image history --no-trunc "$img" 2>/dev/null | grep -q 'entrypoint.sh' \
            || { ok=0; fail "R17 $img does not look like a local build of this repo"; }
    done
    [ $ok -eq 1 ] && pass "R17 all three images are local builds of this repository"

    # R18 inter-service reachability on the bridge network
    ok=1
    docker exec wordpress nc -z mariadb 3306   2>/dev/null || { ok=0; fail "R18 wordpress cannot reach mariadb:3306"; }
    docker exec nginx     nc -z wordpress 9000 2>/dev/null || { ok=0; fail "R18 nginx cannot reach wordpress:9000"; }
    [ $ok -eq 1 ] && pass "R18 service-name DNS + reachability across the docker network"
fi

# ─────────────────────────────────────────────────────────────────────
section "[D] Deep (crash-restart & persistence)"
# ─────────────────────────────────────────────────────────────────────

if [ $DEEP -eq 0 ]; then
    skip "D** run with --deep (or 'make test-deep') to exercise crash-restart and persistence"
elif [ $RUNNING -eq 0 ]; then
    skip "D** stack not running"
else
    # D01 containers come back after their PID 1 dies
    ok=1
    for c in nginx wordpress mariadb; do
        BEFORE=$(docker inspect --format '{{.Created}}{{.State.StartedAt}}' "$c")
        docker exec "$c" kill 1 2>/dev/null || true
        i=0; back=0
        while [ $i -lt 20 ]; do
            sleep 1
            NOW=$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null || echo gone)
            AFTER=$(docker inspect --format '{{.Created}}{{.State.StartedAt}}' "$c" 2>/dev/null || echo x)
            if [ "$NOW" = "running" ] && [ "$AFTER" != "$BEFORE" ]; then back=1; break; fi
            i=$((i+1))
        done
        [ $back -eq 1 ] || { ok=0; fail "D01 $c did not restart after PID 1 was killed"; }
    done
    [ $ok -eq 1 ] && pass "D01 all containers auto-restart after their main process dies"

    # wait for the stack to settle again
    i=0
    while [ $i -lt 45 ]; do
        CODE=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 2 "https://$DOMAIN/" 2>/dev/null || echo 000)
        [ "$CODE" = "200" ] && break
        sleep 2; i=$((i+1))
    done

    # D02 data survives a full down/up cycle
    STAMP="persist-$(date +%s)"
    docker exec wordpress wp --allow-root --path=/var/www/html option update inception_persist "$STAMP" >/dev/null 2>&1
    docker exec wordpress sh -c "echo $STAMP > /var/www/html/wp-content/persist_check.txt" 2>/dev/null
    docker compose -f "$COMPOSE_FILE" down  >/dev/null 2>&1
    docker compose -f "$COMPOSE_FILE" up -d >/dev/null 2>&1
    i=0
    while [ $i -lt 60 ]; do
        CODE=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 2 "https://$DOMAIN/" 2>/dev/null || echo 000)
        [ "$CODE" = "200" ] && break
        sleep 2; i=$((i+1))
    done
    GOT=$(docker exec wordpress wp --allow-root --path=/var/www/html option get inception_persist 2>/dev/null)
    FGOT=$(docker exec wordpress cat /var/www/html/wp-content/persist_check.txt 2>/dev/null)
    if [ "$GOT" = "$STAMP" ] && [ "$FGOT" = "$STAMP" ]; then
        pass "D02 database rows and site files survive docker compose down/up"
    else
        fail "D02 persistence broken" "db='$GOT' file='$FGOT' expected='$STAMP'"
    fi
    docker exec wordpress sh -c 'rm -f /var/www/html/wp-content/persist_check.txt' 2>/dev/null
    docker exec wordpress wp --allow-root --path=/var/www/html option delete inception_persist >/dev/null 2>&1
fi

# ─────────────────────────────────────────────────────────────────────
printf "\n${BLU}══ Summary ══${RST}  ${GRN}%d passed${RST}  ${RED}%d failed${RST}  ${YLW}%d warnings${RST}  ${DIM}%d skipped${RST}\n" "$PASS" "$FAIL" "$WARN" "$SKIP"
[ $FAIL -gt 254 ] && exit 254
exit $FAIL
