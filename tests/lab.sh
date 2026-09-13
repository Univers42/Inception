#!/bin/hellish
# shellcheck shell=sh
#
# tests/lab.sh — the lab bonus (web + api) against the running stack.
# Everything goes through the edge nginx over TLS, like a browser would, except
# the checks that must look inside a container (PID 1, uid, Redis keys).
#
#   make test-lab                 # ~35 s, read-mostly (creates one flight)
#   make test-lab LAB_ARGS=--deep # + SIGTERM drain and a slow-MariaDB start
set -u

cd "$(dirname "$0")/.." || exit 1

DEEP=0
for arg in "$@"; do
    case "$arg" in
        --deep) DEEP=1 ;;
        -h|--help)
            echo "usage: $0 [--deep]"
            echo "  --deep  also stop the api (SIGTERM drain) and restart it behind a stopped MariaDB"
            exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

if [ -t 1 ]; then
    RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; BLU='\033[1;34m'; DIM='\033[2m'; RST='\033[0m'
else
    RED=''; GRN=''; YLW=''; BLU=''; DIM=''; RST=''
fi
PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); printf "  ${GRN}✔${RST} %s\n" "$1"; }
fail() { FAIL=$((FAIL+1)); printf "  ${RED}✘${RST} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${DIM}%s${RST}\n" "$2"; }
skip() { SKIP=$((SKIP+1)); printf "  ${DIM}– %s (skipped)${RST}\n" "$1"; }
note() { printf "      ${DIM}%s${RST}\n" "$1"; }
section() { printf "\n${BLU}%s${RST}\n" "$1"; }

LOGIN=$(sed -n 's/^LOGIN[[:space:]]*=[[:space:]]*//p' Makefile | head -1)
DOMAIN=$(sed -n 's/^DOMAIN_NAME=//p' srcs/.env 2>/dev/null | head -1)
[ -n "$DOMAIN" ] || DOMAIN="$LOGIN.42.fr"
PORT="${HTTPS_PORT:-443}"
BASE="https://$DOMAIN:$PORT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# every request is resolved to loopback, so no /etc/hosts entry is needed
c() { curl -ks --max-time 10 --resolve "$DOMAIN:$PORT:127.0.0.1" "$@"; }
code() { c -o /dev/null -w '%{http_code}' "$@"; }
header() { c -o /dev/null -D - "$2" | tr -d '\r' | sed -n "s/^$1: *//Ip" | head -1; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null; }
wait_healthy() {
    i=0
    while [ $i -lt "$2" ]; do
        [ "$(health "$1")" = healthy ] && return 0
        sleep 1; i=$((i+1))
    done
    return 1
}
rcli() { docker exec redis redis-cli "$@" 2>/dev/null; }
# stream <seconds>: the traffic event stream, to stdout (curl itself, so $! is curl)
stream() { curl -ksN --max-time "$1" --resolve "$DOMAIN:$PORT:127.0.0.1" "$BASE/api/v1/traffic" 2>/dev/null; }
# sum_n <capture> <wire>: requests on one wire over every frame of a capture
sum_n() { grep -o "\"$2\":{\"n\":[0-9]*" "$1" | sed 's/.*://' | awk '{s += $1} END {print s + 0}'; }
# Wait out a fixed rate-limit window that is already nearly spent, so the
# suite can be run again straight away. $1 = bucket, $2 = threshold.
rl_wait() {
    for k in $(rcli --scan --pattern "lab:rl:$1:*"); do
        n=$(rcli GET "$k"); t=$(rcli TTL "$k")
        if [ "${n:-0}" -gt "$2" ] && [ "${t:-0}" -gt 0 ]; then
            note "the $1 rate-limit window already holds $n requests; waiting ${t}s for it to reset"
            sleep $((t + 1))
        fi
    done
}

for s in web api mariadb redis nginx; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$s" 2>/dev/null)" != true ]; then
        echo "the stack is not running ($s is down): make up" >&2
        exit 1
    fi
done
printf "lab tests against %s\n" "$BASE"

section "containers"
for s in web api; do
    h=$(health "$s")
    if [ "$h" = healthy ]; then pass "L01 $s is healthy (its own HEALTHCHECK)"; else fail "L01 $s is not healthy" "$h"; fi
done
p1=$(docker exec web cat /proc/1/comm 2>/dev/null)
u1=$(docker exec web awk '/^Uid:/{print $2}' /proc/1/status 2>/dev/null)
if [ "$p1" = nginx ] && [ "$u1" != 0 ]; then pass "L02 web: PID 1 is nginx, running as uid $u1 (not root)"; else fail "L02 web PID 1 / uid" "comm=$p1 uid=$u1"; fi
p1=$(docker exec api cat /proc/1/cmdline 2>/dev/null | tr '\0' ' ')
u1=$(docker exec api awk '/^Uid:/{print $2}' /proc/1/status 2>/dev/null)
case "$p1" in
    node\ *) if [ "$u1" != 0 ]; then pass "L03 api: PID 1 is node, privileges dropped to uid $u1"; else fail "L03 api still runs as root"; fi ;;
    *) fail "L03 api PID 1 is not node" "cmdline=$p1" ;;
esac
pub=$(docker port web; docker port api)
if [ -z "$pub" ]; then pass "L04 web and api publish no port (reachable only through nginx)"; else fail "L04 web/api publish ports" "$pub"; fi

section "edge"
s=$(code "$BASE/lab/")
if [ "$s" = 200 ]; then pass "L05 GET /lab/ through nginx → 200"; else fail "L05 GET /lab/" "status $s"; fi
t12=$(c --tlsv1.2 --tls-max 1.2 -o /dev/null -w '%{http_code}' "$BASE/api/v1/healthz")
t13=$(c --tlsv1.3 -o /dev/null -w '%{http_code}' "$BASE/api/v1/healthz")
t11=$(c --tlsv1.1 --tls-max 1.1 -o /dev/null -w '%{http_code}' "$BASE/api/v1/healthz")
if [ "$t12" = 200 ] && [ "$t13" = 200 ] && [ "$t11" = 000 ]; then
    pass "L06 TLS 1.2 and 1.3 accepted, TLS 1.1 refused"
else
    fail "L06 TLS versions" "1.2=$t12 1.3=$t13 1.1=$t11 (want 200 200 000)"
fi
csp=$(header content-security-policy "$BASE/lab/")
case "$csp" in
    *"script-src 'self'"*) case "$csp" in *unsafe-inline*) fail "L07 CSP allows unsafe-inline" "$csp" ;; *) pass "L07 /lab/ has a CSP without unsafe-inline" ;; esac ;;
    *) fail "L07 /lab/ has no script-src 'self' CSP" "$csp" ;;
esac
c "$BASE/lab/" > "$TMP/home.html"
inline=$(grep -o '<script[^>]*>' "$TMP/home.html" | grep -vc 'src=')
styles=$(grep -c '<style\| style="' "$TMP/home.html")
if [ "$inline" = 0 ] && [ "$styles" = 0 ]; then pass "L08 no inline <script>, <style> or style= in the page"; else fail "L08 inline code in /lab/" "scripts=$inline styles=$styles"; fi
third=$(grep -oE '(src|href)="https?://[^"]*"' "$TMP/home.html" | grep -v "//$DOMAIN" | head -3)
if [ -z "$third" ]; then pass "L09 the page loads nothing from another origin"; else fail "L09 third-party resources" "$third"; fi
asset=$(grep -o '/lab/_astro/[^"]*\.js' "$TMP/home.html" | head -1)
cc=$(header cache-control "$BASE$asset")
hc=$(header cache-control "$BASE/lab/")
case "$cc" in
    *immutable*) if [ "$hc" = no-cache ]; then pass "L10 hashed assets immutable, HTML no-cache"; else fail "L10 HTML cache-control" "$hc"; fi ;;
    *) fail "L10 asset cache-control" "$asset: $cc" ;;
esac
total=0
for a in $(grep -o '/lab/_astro/[^"]*\.js' "$TMP/home.html" | sort -u); do
    n=$(c -H 'Accept-Encoding: gzip' -o /dev/null -w '%{size_download}' "$BASE$a")
    total=$((total + n))
done
if [ "$total" -gt 0 ] && [ "$total" -lt 30000 ]; then pass "L11 JavaScript on /lab/ is $total bytes gzipped (budget 30 000)"; else fail "L11 JavaScript budget" "$total bytes"; fi

section "api"
c "$BASE/api/v1/healthz" > "$TMP/h.json"
if grep -q '"ok":true,"mariadb":{"ok":true' "$TMP/h.json" && grep -q '"redis":{"ok":true' "$TMP/h.json"; then
    pass "L12 /api/v1/healthz: MariaDB and Redis both answer"
else
    fail "L12 healthz" "$(cat "$TMP/h.json")"
fi

rl_wait flights 6
rcli DEL lab:flights:all:v1 > /dev/null
docker exec redis timeout 4 redis-cli MONITOR > "$TMP/monitor.txt" 2>/dev/null &
MON=$!
sleep 1
x1=$(header x-cache "$BASE/api/v1/flights")
if [ "$x1" = HIT ]; then
    note "first read was already a HIT (another client refilled the key); deleting and retrying once"
    rcli DEL lab:flights:all:v1 > /dev/null
    x1=$(header x-cache "$BASE/api/v1/flights")
fi
x2=$(header x-cache "$BASE/api/v1/flights")
ttl=$(rcli TTL lab:flights:all:v1)
wait $MON 2>/dev/null
if [ "$x1" = MISS ] && [ "$x2" = HIT ] && [ "${ttl:-0}" -gt 0 ] && [ "${ttl:-0}" -le 60 ]; then
    pass "L13 cache-aside: MISS then HIT on lab:flights:all:v1 (TTL ${ttl}s of 60)"
    note "redis MONITOR, the two requests:"
    grep -E '"(GET|SET)" "lab:flights:all:v1"' "$TMP/monitor.txt" | sed 's/^[0-9.]* \[[^]]*\] //' | cut -c1-90 | head -4 | while read -r line; do note "  $line"; done
else
    fail "L13 cache-aside" "first=$x1 second=$x2 ttl=$ttl"
fi
s=$(c -o "$TMP/post.json" -w '%{http_code}' -X POST -H 'content-type: application/json' \
    -d '{"origin":"nginx","destination":"api","payload_kb":3,"note":"tests/lab.sh"}' "$BASE/api/v1/flights")
x3=$(header x-cache "$BASE/api/v1/flights")
if [ "$s" = 201 ] && [ "$x3" = MISS ]; then pass "L14 POST /flights → 201, and the list is invalidated (next GET is a MISS)"; else fail "L14 write invalidation" "post=$s next=$x3 $(cat "$TMP/post.json")"; fi
id=$(sed -n 's/.*"id":\([0-9]*\).*/\1/p' "$TMP/post.json")
if [ -n "$id" ] && [ "$(code "$BASE/api/v1/flights/$id")" = 200 ]; then pass "L15 GET /flights/$id → 200"; else fail "L15 GET the new flight" "id=$id"; fi

body=$(c -X POST -H 'content-type: application/json' -d '{"origin":"nginx","destination":"moon"}' "$BASE/api/v1/flights")
case "$body" in
    *'"field":"destination"'*) pass "L16 422 names the offending field (destination)" ;;
    *) fail "L16 422 body" "$body" ;;
esac
body=$(c -X POST -H 'content-type: application/json' -d '{"origin":"nginx","destination":"api","colour":"red"}' "$BASE/api/v1/flights")
case "$body" in
    *'"code":"unknown_field"'*'"field":"colour"'*) pass "L17 unknown fields are rejected by name (colour)" ;;
    *) fail "L17 unknown field" "$body" ;;
esac
s=$(code -X DELETE "$BASE/api/v1/flights")
allow=$(c -o /dev/null -D - -X DELETE "$BASE/api/v1/flights" | tr -d '\r' | sed -n 's/^allow: *//Ip')
if [ "$s" = 405 ] && [ -n "$allow" ]; then pass "L18 wrong method → 405 with Allow: $allow"; else fail "L18 405" "status=$s allow=$allow"; fi

pwd_db=$(cat secrets/db_root_password.txt 2>/dev/null)
durable=$(docker exec mariadb mariadb -N -u root -p"$pwd_db" -e "SELECT value FROM lab.stats WHERE name='http_requests'" 2>/dev/null)
if [ "${durable:-0}" -gt 0 ] 2>/dev/null; then pass "L19 counters are durable: lab.stats.http_requests = $durable in MariaDB"; else fail "L19 durable counters" "value=$durable"; fi

hist=$(docker history --no-trunc api:inception 2>/dev/null; docker history --no-trunc web:inception 2>/dev/null)
leak=0
for f in secrets/api_db_password.txt secrets/db_password.txt secrets/db_root_password.txt; do
    v=$(cat "$f" 2>/dev/null)
    [ -n "$v" ] && printf '%s' "$hist" | grep -qF "$v" && leak=1
done
if [ $leak = 0 ]; then pass "L20 no secret value appears in the web or api image history"; else fail "L20 a secret is baked into an image layer"; fi

# last: the fixed window must trip. It uses the guestbook bucket (5/min) so the
# flight checks above stay repeatable; invalid bodies are enough — the limit is
# counted before validation — so no rows are created.
last=""
i=0
while [ $i -lt 12 ]; do
    last=$(c -o "$TMP/rl.json" -D "$TMP/rl.h" -w '%{http_code}' -X POST -H 'content-type: application/json' -d '{}' "$BASE/api/v1/guestbook")
    [ "$last" = 429 ] && break
    i=$((i+1))
done
ra=$(tr -d '\r' < "$TMP/rl.h" | sed -n 's/^retry-after: *//Ip')
if [ "$last" = 429 ] && [ -n "$ra" ]; then pass "L21 rate limit (guestbook, 5/min): 429 with Retry-After: $ra"; else fail "L21 rate limit" "last=$last retry-after=$ra"; fi

section "wires"
# Not buffered: nginx would hold a 1 KB hello and 200-byte frames until its
# buffer filled or the response ended, and 1.5 s would show nothing.
stream 1.5 > "$TMP/tr1.txt"
frames=$(grep -c '^event: traffic' "$TMP/tr1.txt")
if grep -q '^event: hello' "$TMP/tr1.txt" && [ "$frames" -ge 2 ]; then
    pass "L24 /api/v1/traffic streams through nginx unbuffered: hello + $frames frames in 1.5 s"
else
    fail "L24 traffic stream" "hello=$(grep -c '^event: hello' "$TMP/tr1.txt") frames=$frames in 1.5 s"
fi

stream 4 > "$TMP/tr2.txt" &
TR=$!
sleep 1
i=0
while [ $i -lt 20 ]; do c -o /dev/null "$BASE/api/v1/flights"; i=$((i+1)); done
wait $TR
n=$(sum_n "$TMP/tr2.txt" 'nginx>api')
hits=$(grep -o '"nginx>api":{"n":[0-9]*,"k":{[^}]*}' "$TMP/tr2.txt" | grep -o '"hit":[0-9]*' | sed 's/.*://' | awk '{s += $1} END {print s + 0}')
if [ "$n" -ge 20 ] && [ "$hits" -ge 15 ]; then
    pass "L25 nginx → api counts every request with its outcome: 20 GET /flights sent, $n seen, $hits cache hits"
else
    fail "L25 nginx → api wire" "20 sent, $n seen, $hits hits"
fi

# php-fpm counts a request from nginx twice (fastcgi_keep_conn); the API
# divides by config.fpm.countsPerRequest. Ten page views must read as ten,
# plus at most nginx's own healthcheck and a wp-cron spawn.
stream 6 > "$TMP/tr3.txt" &
TR=$!
sleep 1.5
i=0
while [ $i -lt 10 ]; do c -o /dev/null "$BASE/wp-login.php"; i=$((i+1)); done
wait $TR
n=$(sum_n "$TMP/tr3.txt" 'nginx>wordpress')
if [ "$n" -ge 10 ] && [ "$n" -le 13 ]; then
    pass "L26 nginx → wordpress, sampled from php-fpm: 10 page views read as $n"
else
    fail "L26 nginx → wordpress count" "10 page views read as $n (check config.fpm.countsPerRequest against fastcgi_keep_conn)"
fi

st=$(c -o "$TMP/fpm.txt" -w '%{http_code}' "$BASE/fpm-status?json")
if grep -q 'accepted conn' "$TMP/fpm.txt"; then fail "L27 php-fpm's status page is reachable through nginx" "GET /fpm-status → $st"
else pass "L27 php-fpm's status page is not reachable through nginx (GET /fpm-status → $st)"; fi

pids=""
i=0
# curl itself in the background (not the stream function), so $! is what kill must reach
while [ $i -lt 4 ]; do
    curl -ksN --max-time 10 --resolve "$DOMAIN:$PORT:127.0.0.1" "$BASE/api/v1/traffic" > /dev/null 2>&1 &
    pids="$pids $!"
    i=$((i+1))
done
sleep 1.5
s5=$(c -o "$TMP/cap.json" --max-time 3 -w '%{http_code}' "$BASE/api/v1/traffic")
# shellcheck disable=SC2086
kill $pids 2>/dev/null
wait 2>/dev/null
if [ "$s5" = 429 ] && grep -q too_many_streams "$TMP/cap.json"; then
    pass "L28 a fifth stream from one address is refused: 429 too_many_streams"
else
    fail "L28 per-address stream cap" "fifth stream → $s5 $(head -c 120 "$TMP/cap.json")"
fi

section "lifecycle"
if [ $DEEP = 1 ]; then
    since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    stream 30 > "$TMP/bye.txt" &
    BYE=$!
    sleep 1
    t0=$(date +%s)
    docker stop -t 15 api > /dev/null
    took=$(( $(date +%s) - t0 ))
    wait $BYE
    ec=$(docker inspect -f '{{.State.ExitCode}}' api)
    logs=$(docker logs --since "$since" api 2>&1)
    case "$logs" in
        *'shutdown: complete'*)
            if [ "$ec" = 0 ] && grep -q '^event: bye' "$TMP/bye.txt" && [ "$took" -le 5 ]; then
                pass "L22 SIGTERM with a traffic stream open: the stream gets 'bye', api drains and exits 0 in ${took} s"
            else
                fail "L22 SIGTERM" "exit=$ec bye=$(grep -c '^event: bye' "$TMP/bye.txt") took=${took}s (a stream must not hold the drain)"
            fi ;;
        *) fail "L22 SIGTERM: no 'shutdown: complete' in the logs" "exit=$ec" ;;
    esac
    docker stop mariadb > /dev/null
    docker start api > /dev/null
    sleep 8
    st=$(docker inspect -f '{{.State.Status}}' api)
    docker start mariadb > /dev/null
    if [ "$st" = running ] && wait_healthy mariadb 90 && wait_healthy api 90; then
        pass "L23 api started before MariaDB: it waited (bounded loop), then became healthy"
    else
        fail "L23 api with a late MariaDB" "api was $st after 8 s; now $(health api)"
    fi
    wait_healthy wordpress 90 > /dev/null || docker start wordpress > /dev/null
else
    skip "L22 SIGTERM drain (--deep)"
    skip "L23 api waits for a late MariaDB (--deep)"
fi

printf "\n  ${GRN}%d passed${RST}  ${RED}%d failed${RST}  ${DIM}%d skipped${RST}\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
