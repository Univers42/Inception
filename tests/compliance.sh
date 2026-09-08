#!/bin/hellish
set -u

cd "$(dirname "$0")/.." || exit 1

DEEP=0
NO_CLONE="${NO_CLONE:-0}"
for arg in "$@"; do
    case "$arg" in
        --deep)     DEEP=1 ;;
        --no-clone) NO_CLONE=1 ;;
        -h|--help)
            echo "usage: $0 [--deep] [--no-clone]"
            echo "  --deep      also exercise crash-restart and persistence"
            echo "  --no-clone  skip the preliminary checks, which clone the repository"
            exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

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
ALL_DOCKERFILES=$(ls srcs/requirements/*/Dockerfile srcs/requirements/*/*/Dockerfile 2>/dev/null)
ALL_ENTRYPOINTS=$(ls srcs/requirements/*/tools/*.sh srcs/requirements/*/*/tools/*.sh 2>/dev/null)
ENTRYPOINT_FILES=$(ls srcs/requirements/*/tools/entrypoint.sh srcs/requirements/*/*/tools/entrypoint.sh 2>/dev/null)

printf "${BLU}══ Inception compliance suite ══${RST}  login=%s domain=%s\n" "$LOGIN" "$DOMAIN"

section "[P] Preliminary tests (what happens before anything else)"
PRELIM_DIR=""
cleanup_prelim() { [ -n "$PRELIM_DIR" ] && rm -rf "$PRELIM_DIR"; }
trap cleanup_prelim EXIT

if [ "${NO_CLONE:-0}" = "1" ]; then
    skip "P** --no-clone / NO_CLONE=1 — the preliminary checks need to clone the repository"
else
    ORIGIN_URL=$(git remote get-url origin 2>/dev/null)
    CLONE_URL=$(printf '%s' "$ORIGIN_URL" | sed -E 's#^git@([^:]+):#https://\1/#')

    PRELIM_DIR=$(mktemp -d)
    if [ -z "$CLONE_URL" ]; then
        fail "P01 no 'origin' remote — there is nothing for an evaluator to clone"
    elif ! git clone -q "$CLONE_URL" "$PRELIM_DIR/repo" 2>/dev/null; then
        warn "P01 could not clone $CLONE_URL (offline?) — preliminary checks skipped"
        PRELIM_DIR=""
    else
        C="$PRELIM_DIR/repo"
        pass "P01 the repository clones cleanly from $CLONE_URL"

        LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null)
        CLONE_HEAD=$(git -C "$C" rev-parse HEAD 2>/dev/null)
        if [ "$LOCAL_HEAD" = "$CLONE_HEAD" ]; then
            pass "P02 the clone is at the same commit as this tree ($(printf '%.7s' "$CLONE_HEAD"))"
        else
            AHEAD=$(git rev-list --count "$CLONE_HEAD..$LOCAL_HEAD" 2>/dev/null || echo '?')
            fail "P02 the clone is $AHEAD commit(s) BEHIND this tree — that work is not submitted" \
                 "local $(printf '%.7s' "$LOCAL_HEAD") vs clone $(printf '%.7s' "$CLONE_HEAD"); push before the defence"
        fi
        DIRTY=$(git status --porcelain 2>/dev/null | grep -vE '^\?\? (secrets/|srcs/\.env)' | wc -l)
        [ "$DIRTY" -eq 0 ] || warn "P02 $DIRTY uncommitted change(s) in this tree are not in the clone"

        ok=1
        for f in Makefile srcs/docker-compose.yml README.md USER_DOC.md DEV_DOC.md; do
            [ -f "$C/$f" ] || { ok=0; fail "P03 the clone is missing $f"; }
        done
        for d in srcs srcs/requirements secrets; do
            case "$d" in
                secrets) continue ;;
            esac
            [ -d "$C/$d" ] || { ok=0; fail "P03 the clone is missing the directory $d/"; }
        done
        for svc in nginx wordpress mariadb; do
            [ -f "$C/srcs/requirements/$svc/Dockerfile" ] \
                || { ok=0; fail "P03 the clone is missing srcs/requirements/$svc/Dockerfile"; }
        done
        [ $ok -eq 1 ] && pass "P03 the clone has the expected files, directories and names"

        ok=1
        ENVS=$(cd "$C" && git ls-files | grep -E '(^|/)\.env$' || true)
        [ -z "$ENVS" ] || { ok=0; fail "P04 a .env file is committed to the repository" "$ENVS"; }
        SEC=$(cd "$C" && git ls-files | grep -E '(^|/)secrets/' || true)
        [ -z "$SEC" ] || { ok=0; fail "P04 files under secrets/ are committed" "$SEC"; }
        KEYS=$(cd "$C" && git ls-files | grep -E '\.(key|pem|p12|pfx)$' || true)
        [ -z "$KEYS" ] || { ok=0; fail "P04 private key material is committed" "$KEYS"; }
        HITS=""
        for f in secrets/db_password.txt secrets/db_root_password.txt \
                 secrets/credentials.txt secrets/ftp_password.txt; do
            [ -f "$f" ] || continue
            while IFS= read -r v; do
                [ ${#v} -ge 8 ] || continue
                grep -rqF -- "$v" "$C" 2>/dev/null && HITS="$HITS
tree:$(basename "$f")"
                git -C "$C" log --all -p 2>/dev/null | grep -qF -- "$v" \
                    && HITS="$HITS
history:$(basename "$f")"
            done < "$f"
        done
        HITS=$(printf '%s' "$HITS" | grep -v '^$' | sort -u)
        [ -z "$HITS" ] || { ok=0; fail "P04 a LIVE credential value is published in the repository" "$HITS"; }
        [ $ok -eq 1 ] && pass "P04 no .env, no secrets/, no key files and no live credential value in the clone or its history"
    fi

    skip "P05 'defense can only happen if the student is present' — not machine-verifiable, by nature"
fi

section "[S] Structure & Makefile"

ok=1
for f in Makefile "$COMPOSE_FILE" srcs/.env \
         secrets/db_password.txt secrets/db_root_password.txt secrets/credentials.txt; do
    [ -f "$f" ] || { ok=0; fail "S01 missing: $f"; }
done
for d in secrets srcs srcs/requirements; do
    [ -d "$d" ] || { ok=0; fail "S01 missing directory: $d/"; }
done
[ -f .env ] && { ok=0; fail "S01 .env must live in srcs/, not at the repository root"; }
for s in nginx wordpress mariadb; do
    [ -f "srcs/requirements/$s/Dockerfile" ]          || { ok=0; fail "S01 missing Dockerfile for $s"; }
    [ -f "srcs/requirements/$s/tools/entrypoint.sh" ] || { ok=0; fail "S01 missing entrypoint for $s"; }
    [ -d "srcs/requirements/$s/conf" ]                || { ok=0; fail "S01 missing conf/ for $s"; }
    [ -d "srcs/requirements/$s/tools" ]               || { ok=0; fail "S01 missing tools/ for $s"; }
    [ -f "srcs/requirements/$s/.dockerignore" ] \
        || { ok=0; fail "S01 missing .dockerignore for $s (the subject's tree shows one)"; }
done
[ $ok -eq 1 ] && pass "S01 layout matches the subject's tree (Makefile, secrets/, srcs/requirements/<svc>/{Dockerfile,conf,tools})"

ok=1
for f in README.md USER_DOC.md DEV_DOC.md; do
    [ -f "$f" ] || { ok=0; fail "S02 missing: $f"; }
done
if [ -f README.md ]; then
    head -1 README.md | grep -q '^\*This project has been created as part of the 42 curriculum by .*\*$' \
        || { ok=0; fail "S02 README first line must be the italicised 42-curriculum sentence"; }
fi
[ $ok -eq 1 ] && pass "S02 README.md + USER_DOC.md + DEV_DOC.md present, README header compliant"

ok=1
if [ -f README.md ]; then
    FIRST=$(head -1 README.md)
    printf '%s' "$FIRST" | grep -qE '^\*[^*].*\*$' \
        || { ok=0; fail "S25 README first line is not italicised with single asterisks" "$FIRST"; }
    printf '%s' "$FIRST" | grep -qF "$LOGIN" \
        || { ok=0; fail "S25 README first line does not name the login '$LOGIN'" "$FIRST"; }
    for sect in "Description" "Instructions" "Resources" "Project description"; do
        grep -qiE "^#{1,4}[[:space:]]+.*${sect}" README.md \
            || { ok=0; fail "S25 README has no '$sect' section"; }
    done
    grep -qiE '^#{1,4}[[:space:]]+.*(AI|artificial intelligence)' README.md \
        || grep -qiE '\b(AI was used|use of AI|AI usage)\b' README.md \
        || { ok=0; fail "S25 README does not describe how AI was used (required in Resources)"; }
    for cmp in "Virtual Machines vs Docker" "Secrets vs Environment Variables" \
               "Docker Network vs Host Network" "Docker Volumes vs Bind Mounts"; do
        grep -qiF "$cmp" README.md \
            || { ok=0; fail "S25 README is missing the comparison '$cmp'"; }
    done
fi
[ $ok -eq 1 ] && pass "S25 README has the mandated sections, AI usage and all four comparisons"

ok=1
check_topic() {
    grep -qiE "$3" "$1" || { ok=0; fail "S26 $1 does not cover: $2"; }
}
if [ -f USER_DOC.md ]; then
    check_topic USER_DOC.md "what services the stack provides"  '(nginx|wordpress|mariadb).*(service|container)|services (provided|the stack)|what you get'
    check_topic USER_DOC.md "starting and stopping the project" '(make (up|down|start|stop))|start(ing)? and stop(ping)?'
    check_topic USER_DOC.md "accessing the site and admin panel" 'wp-admin|admin(istration)? panel'
    check_topic USER_DOC.md "locating and managing credentials"  'credential|secrets/'
    check_topic USER_DOC.md "checking the services run correctly" 'docker ps|healthy|health|running correctly'
fi
if [ -f DEV_DOC.md ]; then
    check_topic DEV_DOC.md "environment setup from scratch"      'from scratch|prerequisite'
    check_topic DEV_DOC.md "configuration files and secrets"     '\.env|secrets'
    check_topic DEV_DOC.md "building via Makefile and Compose"   'docker compose|docker-compose'
    check_topic DEV_DOC.md "managing containers and volumes"     'docker volume|docker exec'
    check_topic DEV_DOC.md "where data is stored and persistence" 'persist|/home/[^/]*/data'
fi
[ $ok -eq 1 ] && pass "S26 USER_DOC.md and DEV_DOC.md cover every point the subject lists"

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

S04HITS=$(grep -hnE '(^FROM.*:latest|image:.*:latest)' $ALL_DOCKERFILES "$COMPOSE_FILE" 2>/dev/null || true)
S04IMPLICIT=$(awk '/^FROM[[:space:]]/ {
        ref=$2
        if (ref !~ /:/ && ref !~ /@/ && ref !~ /^\$/)
            print FILENAME ": " $0 "   (untagged = :latest)"
    }' $ALL_DOCKERFILES 2>/dev/null || true)
if [ -n "$S04HITS$S04IMPLICIT" ]; then
    fail "S04 ':latest' tag found (explicit or implicit)" "$S04HITS
$S04IMPLICIT"
else
    pass "S04 no ':latest' anywhere; every FROM is explicitly tagged"
fi

svc_block() {
    awk -v tgt="  $1:" '$0==tgt{f=1;next} f && /^  [a-zA-Z0-9_-]+:[[:space:]]*$/{f=0} f' "$COMPOSE_FILE"
}

ok=1
for s in nginx wordpress mariadb; do
    svc_block "$s" | grep -q 'build:' || { ok=0; fail "S05 service $s has no build: directive"; }
done
FROMS=$(grep -h '^FROM' $DOCKERFILES | awk '{print $2}' | grep -vE '^(alpine|debian):' || true)
[ -n "$FROMS" ] && { ok=0; fail "S05 non-Alpine/Debian base image" "$FROMS"; }
[ $ok -eq 1 ] && pass "S05 all services built from local Dockerfiles, bases restricted to Alpine/Debian"

HACK_RE='tail[[:space:]]+-[fF]'
HACK_RE="$HACK_RE"'|sleep[[:space:]]+infinity'
HACK_RE="$HACK_RE"'|sleep[[:space:]]+[0-9]{3,}'
HACK_RE="$HACK_RE"'|while[[:space:]]+(true|:)([[:space:]]*;|[[:space:]]|$)'
HACK_RE="$HACK_RE"'|until[[:space:]]+false'
HACK_RE="$HACK_RE"'|for[[:space:]]*\(\(?[[:space:]]*;;'
HACK_RE="$HACK_RE"'|yes[[:space:]]*(\||>[[:space:]]*/dev/null)'
HACK_RE="$HACK_RE"'|supervisord|s6-svscan|runsvdir|daemontools'
HACK_RE="$HACK_RE"'|systemctl|/sbin/init|openrc'
HACK_RE="$HACK_RE"'|service[[:space:]]+[a-zA-Z0-9_-]+[[:space:]]+start'
HACKS=""
for f in $ALL_DOCKERFILES $ALL_ENTRYPOINTS "$COMPOSE_FILE"; do
    [ -f "$f" ] || continue
    HIT=$(sed -e 's/[[:space:]]*#.*$//' "$f" | grep -nE "$HACK_RE" || true)
    [ -n "$HIT" ] && HACKS="$HACKS
$f: $HIT"
done
if [ -n "$HACKS" ]; then
    fail "S06 prohibited keep-alive hack or process supervisor found" "$HACKS"
else
    pass "S06 no keep-alive hacks or supervisors in any service (bonus included)"
fi

ok=1
grep -q '^networks:' "$COMPOSE_FILE" || { ok=0; fail "S07 top-level 'networks:' line missing"; }
grep -qE 'network_mode:[[:space:]]*host' "$COMPOSE_FILE" && { ok=0; fail "S07 network_mode: host is forbidden"; }
grep -qE '^\s+links:' "$COMPOSE_FILE" && { ok=0; fail "S07 links: is forbidden"; }
SVC_BLOCK=$(awk '/^services:/,/^(volumes|networks):/' "$COMPOSE_FILE")
SVC_N=$(printf '%s\n' "$SVC_BLOCK" | grep -cE '^  [a-zA-Z0-9_-]+:[[:space:]]*$')
NET_N=$(printf '%s\n' "$SVC_BLOCK" | grep -cE '^    networks:')
[ "$SVC_N" = "$NET_N" ] || { ok=0; fail "S07 only $NET_N of $SVC_N services declare 'networks:'"; }
LINKHITS=$(grep -rnE '(^|[[:space:]])[-][-]link([[:space:]]|=)|^[[:space:]]*external_links:' \
    Makefile srcs 2>/dev/null | grep -v '^Binary' || true)
[ -z "$LINKHITS" ] || { ok=0; fail "S07 legacy container-link flag / external_links found" "$LINKHITS"; }
[ $ok -eq 1 ] && pass "S07 networks: present, all $SVC_N services joined, no host networking, no links"

N=$(grep -c 'restart:' "$COMPOSE_FILE")
if [ "$N" -ge 3 ]; then
    pass "S08 restart policy declared on all $N services ($(grep 'restart:' "$COMPOSE_FILE" | awk '{print $2}' | sort -u | tr '\n' ' '))"
else
    fail "S08 restart policy missing on some services (found $N, need one per service)"
fi

ok=1
for s in nginx wordpress mariadb; do
    svc_block "$s" | grep -q "image: *$s:" || { ok=0; fail "S09 image name for service '$s' must be '$s:<tag>'"; }
done
[ $ok -eq 1 ] && pass "S09 each image is named after its service (nginx, wordpress, mariadb)"

ok=1
for s in wordpress mariadb; do
    svc_block "$s" | grep -q '^\s*ports:' && { ok=0; fail "S10 mandatory service '$s' must not publish ports"; }
done
NGINX_PORTS=$(svc_block nginx | awk '/^\s*ports:/{f=1;next} f && /^\s*-/{print;next} f{exit}' | tr -d ' "-')
if [ $ok -eq 1 ] && [ "$NGINX_PORTS" = "443:443" ]; then
    pass "S10 single published port: 443 (nginx)"
else
    ok=0; fail "S10 nginx must publish exactly 443:443" "found: $NGINX_PORTS"
fi

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
[ $ok -eq 1 ] && pass "S11 named volumes (db_data, wp_data and any bonus volume) all under /home/$LOGIN/data, no service bind mounts"

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

S13RE='(pass(wd|word)?|secret|api[_-]?key|token|credential)[[:space:]]*='
S13RE="$S13RE"'|^[[:space:]]*(ENV|ARG)[[:space:]]+[A-Z_]*(PASS|SECRET|TOKEN|KEY|CRED)'
S13HITS=$(grep -hinE "$S13RE" $ALL_DOCKERFILES 2>/dev/null \
    | grep -viE '_FILE|/run/secrets|\$\{|example|placeholder' || true)
if [ -n "$S13HITS" ]; then
    fail "S13 credential-like content in a Dockerfile" "$S13HITS"
else
    pass "S13 no passwords, API keys or tokens in any Dockerfile"
fi

LEAKS=$(git ls-files -z | xargs -0 grep -inE "(password|passwd|secret|api_key|token)[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9@#%!]{4,}" 2>/dev/null \
        | grep -viE '\$|\{\{|/run/secrets|secrets/|password\.txt|openssl rand|sql_escape|MYSQL_PWD|_FILE|example|placeholder|YourDb|WpAdmin|WpEditor' || true)
if [ -n "$LEAKS" ]; then
    fail "S14 possible plaintext credential in tracked files" "$LEAKS"
else
    pass "S14 no plaintext credentials in tracked files"
fi

HLEAKS=$(git log --all -p -- . 2>/dev/null \
         | grep -iE '^\+.*(password|passwd|secret)[[:space:]]*[:=][[:space:]]*['\''"]?[A-Za-z0-9@#%!]{4,}' \
         | grep -viE '\$|\{|/run/secrets|secrets/|password\.txt|openssl rand|sql_escape|MYSQL_PWD|_FILE|example|placeholder|YourDb|WpAdmin|WpEditor|IDENTIFIED BY' \
         | sort -u | head -5 || true)
if [ -n "$HLEAKS" ]; then
    fail "S15 credential-like lines exist in git HISTORY (rewrite history before submission!)" "$HLEAKS"
else
    pass "S15 git history clean of credential-like content"
fi

ok=1
SECRET_VALUES=""
for f in secrets/db_password.txt secrets/db_root_password.txt secrets/credentials.txt \
         secrets/ftp_password.txt; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
        [ ${#line} -ge 8 ] && SECRET_VALUES="$SECRET_VALUES
$line"
    done < "$f"
done
if [ -f srcs/.env ]; then
    while IFS= read -r line; do
        case "$line" in
            *PASSWORD=*|*PASS=*|*SECRET=*|*TOKEN=*)
                v=${line#*=}
                [ ${#v} -ge 8 ] && SECRET_VALUES="$SECRET_VALUES
$v" ;;
        esac
    done < srcs/.env
fi

if [ -z "$(printf '%s' "$SECRET_VALUES" | tr -d '[:space:]')" ]; then
    warn "S24 no secret values found to check (run make setup first)"
else
    printf '%s\n' "$SECRET_VALUES" | grep -v '^$' | while IFS= read -r v; do
        git grep -qF -- "$v" HEAD 2>/dev/null && echo "COMMITTED:$v"
        git ls-files -z 2>/dev/null | xargs -0 grep -lF -- "$v" 2>/dev/null | grep -q . \
            && echo "WORKTREE:$v"
        git log --all -p 2>/dev/null | grep -qF -- "$v" && echo "HISTORY:$v"
    done > /tmp/.s24hits 2>/dev/null
    HITS=$(cat /tmp/.s24hits 2>/dev/null | sed 's/\(:.\{0,3\}\).*/\1.../'); rm -f /tmp/.s24hits
    if [ -n "$HITS" ]; then
        ok=0; fail "S24 a live secret value is published" "$HITS"
    fi
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q .; then
        printf '%s\n' "$SECRET_VALUES" | grep -v '^$' | while IFS= read -r v; do
            for c in nginx wordpress mariadb; do
                docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null \
                    | grep -qF -- "$v" && echo "ENV:$c"
            done
            for i in nginx:inception wordpress:inception mariadb:inception; do
                docker history --no-trunc "$i" 2>/dev/null | grep -qF -- "$v" && echo "IMAGE:$i"
            done
        done > /tmp/.s24rt 2>/dev/null
        RTHITS=$(sort -u /tmp/.s24rt 2>/dev/null); rm -f /tmp/.s24rt
        [ -n "$RTHITS" ] && { ok=0; fail "S24 a live secret value is embedded in an image or container env" "$RTHITS"; }
    fi
    [ $ok -eq 1 ] && pass "S24 no live secret value appears in tracked files, git history, image layers or container env"
fi

ok=1
grep -q "^DOMAIN_NAME=$DOMAIN" srcs/.env || { ok=0; fail "S16 srcs/.env must define DOMAIN_NAME=$DOMAIN"; }
grep -q '\${DOMAIN_NAME}' "$COMPOSE_FILE" || { ok=0; fail "S16 compose must consume env vars (\${DOMAIN_NAME})"; }
[ $ok -eq 1 ] && pass "S16 .env file present and consumed through compose interpolation"

WPADMIN=$(sed -n 's/^WP_ADMIN_USER=//p' srcs/.env | head -1)
case "$(printf %s "$WPADMIN" | tr '[:upper:]' '[:lower:]')" in
    *admin*) fail "S17 WP_ADMIN_USER '$WPADMIN' contains 'admin' (forbidden)" ;;
    "")      fail "S17 WP_ADMIN_USER not set in srcs/.env" ;;
    *)       pass "S17 WP admin username '$WPADMIN' complies with the naming rule" ;;
esac

ok=1
for e in $ENTRYPOINT_FILES; do
    LAST=$(grep -vE '^\s*(#|$)' "$e" \
        | sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba}' \
        | tail -1)
    case "$LAST" in
        exec\ *) : ;;
        *) ok=0; fail "S18 $e does not end with 'exec <daemon>'" "last line: $LAST" ;;
    esac
done
[ $ok -eq 1 ] && pass "S18 every entrypoint ends with exec — daemon runs as PID 1"

if grep -q 'docker compose -f srcs/docker-compose.yml' Makefile; then
    pass "S19 Makefile builds/starts the stack through srcs/docker-compose.yml"
else
    fail "S19 Makefile must call docker compose with srcs/docker-compose.yml"
fi

ok=1
EXPECT_DOMAIN="${LOGIN}.42.fr"
if [ "$DOMAIN" != "$EXPECT_DOMAIN" ]; then
    ok=0; fail "S20 DOMAIN_NAME is '$DOMAIN'; the subject requires '$EXPECT_DOMAIN'"
fi
RESOLVED=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1)
if [ -z "$RESOLVED" ]; then
    ok=0; fail "$DOMAIN does not resolve on this machine (make setup adds it to /etc/hosts)"
else
    case "$RESOLVED" in
        127.*|::1|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) : ;;
        *) ok=0; fail "S20 $DOMAIN resolves to $RESOLVED, which is not a local address" ;;
    esac
fi
[ $ok -eq 1 ] && pass "S20 $DOMAIN is <login>.42.fr and resolves to $RESOLVED"

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

NGINX_CONF=$(ls srcs/requirements/nginx/conf/*.conf 2>/dev/null | head -1)
if [ -z "$NGINX_CONF" ]; then
    fail "S22 no nginx .conf found under srcs/requirements/nginx/conf/"
else
    PROTOS=$(sed -n 's/^[[:space:]]*ssl_protocols[[:space:]]*\(.*\);.*/\1/p' "$NGINX_CONF" | tr -s ' ')
    if [ -z "$PROTOS" ]; then
        fail "S22 no ssl_protocols directive in $NGINX_CONF (nginx would fall back to its defaults)"
    else
        BAD=$(printf '%s\n' "$PROTOS" | tr ' ' '\n' | grep -viE '^(TLSv1\.2|TLSv1\.3)$' | grep -v '^$' || true)
        if [ -n "$BAD" ]; then
            fail "S22 ssl_protocols allows more than TLSv1.2/1.3" "found: $PROTOS"
        elif printf '%s' "$PROTOS" | grep -q 'TLSv1\.2' && printf '%s' "$PROTOS" | grep -q 'TLSv1\.3'; then
            pass "S22 nginx config pins ssl_protocols to TLSv1.2 TLSv1.3 only"
        else
            fail "S22 ssl_protocols must list both TLSv1.2 and TLSv1.3" "found: $PROTOS"
        fi
    fi
fi

ok=1
for f in $ALL_DOCKERFILES; do
    [ -f "$f" ] || continue
    STARTCMD=$(grep -E '^(CMD|ENTRYPOINT)[[:space:]]' "$f" || true)
    [ -n "$STARTCMD" ] || continue
    VALUE=$(printf '%s' "$STARTCMD" | sed -E 's/^(CMD|ENTRYPOINT)[[:space:]]+//')
    if printf '%s' "$VALUE" | grep -qE '^\[?[[:space:]]*"?(/bin/|/usr/bin/)?(bash|sh|ash|zsh)"?[[:space:]]*\]?$'; then
        ok=0; fail "S23 $f starts a bare shell as the container command" "$STARTCMD"
    fi
    if printf '%s' "$VALUE" | grep -qE "$HACK_RE"; then
        ok=0; fail "S23 $f start command contains a keep-alive hack" "$STARTCMD"
    fi
done
OVERRIDE=$(grep -nE '^[[:space:]]+(command|entrypoint):' "$COMPOSE_FILE" || true)
if [ -n "$OVERRIDE" ]; then
    if printf '%s' "$OVERRIDE" | grep -qE '(bash|/bin/sh|[^a-z]sh)[[:space:]]*$' \
        || printf '%s' "$OVERRIDE" | grep -qE "$HACK_RE"; then
        ok=0; fail "S23 compose command/entrypoint override is a shell or a hack" "$OVERRIDE"
    fi
fi
[ $ok -eq 1 ] && pass "S23 no service starts a bare shell or a keep-alive loop as its command"

section "[R] Runtime"

RUNNING=1
for c in nginx wordpress mariadb; do
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$c" || RUNNING=0
done

if [ $RUNNING -eq 0 ]; then
    skip "R** stack not running — start it with 'make up' to run runtime checks"
else
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

    PUB=$(docker ps --format '{{.Names}} {{.Ports}}' | grep -E '^(nginx|wordpress|mariadb) ' | grep -oE '0\.0\.0\.0:[0-9]+|\[::\]:[0-9]+' | grep -oE '[0-9]+$' | sort -u)
    if [ "$PUB" = "443" ]; then
        pass "R02 port 443 is the only published port"
    else
        fail "R02 published ports must be exactly {443}" "found: $(printf '%s' "$PUB" | tr '\n' ' ')"
    fi

    ok=1
    R03_CONF=$(mktemp)
    cat > "$R03_CONF" <<'R03EOF'
openssl_conf = default_conf
[default_conf]
ssl_conf = ssl_sect
[ssl_sect]
system_default = system_default_sect
[system_default_sect]
MinProtocol = TLSv1
CipherString = DEFAULT@SECLEVEL=0
R03EOF
    for v in tls1 tls1_1; do
        OUT=$(echo | OPENSSL_CONF="$R03_CONF" openssl s_client -connect "$DOMAIN:443" -$v 2>&1)
        if printf '%s' "$OUT" | grep -qE 'Cipher is [A-Z]'; then
            ok=0; fail "R03 $v handshake unexpectedly succeeded — server accepts obsolete TLS"
        elif printf '%s' "$OUT" | grep -qiE 'alert protocol version|wrong version number|unsupported protocol'; then
            :
        elif printf '%s' "$OUT" | grep -qi 'no protocols available'; then
            ok=0
            warn "R03 $v could not be offered by this client — result inconclusive, see S22"
        else
            ok=0; fail "R03 $v gave no clear verdict" "$(printf '%s' "$OUT" | head -2)"
        fi
    done
    rm -f "$R03_CONF"
    for v in tls1_2 tls1_3; do
        if ! echo | openssl s_client -connect "$DOMAIN:443" -$v 2>/dev/null | grep -qE 'Cipher is [A-Z]'; then
            ok=0; fail "R03 $v handshake failed"
        fi
    done
    [ $ok -eq 1 ] && pass "R03 TLSv1.2/1.3 accepted; TLSv1.0/1.1 refused by the server (alert)"

    CERT=$(echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -subject -issuer 2>/dev/null)
    if printf '%s' "$CERT" | grep -q "CN *= *$DOMAIN" && printf '%s' "$CERT" | grep -q "Inception Local CA"; then
        pass "R04 served certificate is CN=$DOMAIN signed by the local CA"
    else
        fail "R04 unexpected certificate" "$CERT"
    fi

    BODY=$(curl -ks --max-time 10 "https://$DOMAIN/")
    SIZE=${#BODY}
    if [ "$SIZE" -gt 10000 ] && printf '%s' "$BODY" | grep -q 'wp-\(content\|includes\)'; then
        pass "R05 https://$DOMAIN serves a real WordPress page ($SIZE bytes)"
    else
        fail "R05 front page missing or empty ($SIZE bytes)"
    fi

    CODE=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 10 "https://$DOMAIN/wp-login.php")
    if [ "$CODE" = "200" ]; then
        pass "R06 admin login page reachable (wp-login.php → 200)"
    else
        fail "R06 wp-login.php returned $CODE"
    fi

    R07CONT=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E ':80->' || true)
    R07ANSWERS=0
    curl -s -o /dev/null --max-time 3 "http://$DOMAIN/" 2>/dev/null && R07ANSWERS=1
    if [ -n "$R07CONT" ]; then
        fail "R07 a container of this project publishes port 80" "$R07CONT"
    elif [ "$R07ANSWERS" = "1" ]; then
        OWNER=$(ss -ltnp 2>/dev/null | grep ':80 ' | grep -oE 'users:\(\("[^"]+"' | head -1 | sed 's/.*"\(.*\)"/\1/')
        warn "R07 something outside this project answers on port 80 ${OWNER:+($OWNER)} — no Inception container publishes it, but an evaluator will see it"
    else
        pass "R07 port 80 closed; nginx:443 is the only entrypoint"
    fi

    ULIST=$(docker exec wordpress wp --allow-root --path=/var/www/html user list --fields=user_login,roles --format=csv 2>/dev/null | tail -n +2)
    NUSERS=$(printf '%s\n' "$ULIST" | grep -c .)
    NADMIN=$(printf '%s\n' "$ULIST" | grep -c ',administrator')
    ADMIN_LOGIN=$(printf '%s\n' "$ULIST" | grep ',administrator' | cut -d, -f1 | paste -sd, -)
    ok=1
    [ "$NUSERS" -eq 2 ] || { ok=0; fail "R08 expected 2 WordPress users, found $NUSERS"; }
    [ "$NADMIN" -eq 1 ] || { ok=0; fail "R08 expected exactly 1 administrator, found $NADMIN"; }
    case "$(printf %s "$ADMIN_LOGIN" | tr '[:upper:]' '[:lower:]')" in
        *admin*|"") ok=0; fail "R08 administrator login '$ADMIN_LOGIN' violates naming rule" ;;
    esac
    [ $ok -eq 1 ] && pass "R08 two WP users; administrator '$ADMIN_LOGIN' complies with naming rule"

    DBQ() {
        printf '%s\n' "$1" | docker exec -i mariadb \
            sh -c 'exec mariadb -u root -p"$(cat /run/secrets/db_root_password)" -N -B "$0"' "$WPDB" 2>/dev/null
    }
    WPDB=$(sed -n 's/^MYSQL_DATABASE=//p' srcs/.env | head -1); : "${WPDB:=wordpress}"
    PFX=$(DBQ "SHOW TABLES;" | grep -E 'users$' | head -1 | sed 's/users$//')
    if [ -z "$PFX" ]; then
        warn "R20 could not read the WordPress tables from MariaDB — skipped"
    else
        ok=1
        DBUSERS=$(DBQ "SELECT COUNT(*) FROM ${PFX}users;")
        DBADMINS=$(DBQ "SELECT u.user_login FROM ${PFX}users u JOIN ${PFX}usermeta m ON m.user_id=u.ID WHERE m.meta_key='${PFX}capabilities' AND m.meta_value LIKE '%administrator%';")
        NDBADM=$(printf '%s\n' "$DBADMINS" | grep -c .)
        DBADMINS=$(printf '%s\n' "$DBADMINS" | paste -sd, - )
        [ "$DBUSERS" = "2" ] || { ok=0; fail "R20 ${PFX}users holds $DBUSERS rows, expected 2"; }
        [ "$NDBADM" = "1" ] || { ok=0; fail "R20 expected exactly 1 administrator in the database, found $NDBADM" "$DBADMINS"; }
        case "$(printf %s "$DBADMINS" | tr '[:upper:]' '[:lower:]')" in
            *admin*|"") ok=0; fail "R20 administrator user_login '$DBADMINS' contains 'admin'" ;;
        esac
        OTHER=$(DBQ "SELECT CONCAT(user_nicename,' ',display_name) FROM ${PFX}users WHERE user_login='${DBADMINS}';")
        case "$(printf %s "$OTHER" | tr '[:upper:]' '[:lower:]')" in
            *admin*) warn "R20 administrator's nicename/display name contains 'admin' ($OTHER) — the rule targets the username, but expect the question" ;;
        esac
        [ $ok -eq 1 ] && pass "R20 database itself holds 2 users, 1 administrator ('$DBADMINS'), name complies"
    fi

    if docker exec wordpress wp --allow-root --path=/var/www/html theme list --status=active --field=name 2>/dev/null | grep -q .; then
        pass "R09 an active WordPress theme is installed"
    else
        fail "R09 no active theme — the site would render a blank page"
    fi

    ok=1
    R10_PAIRS='nginx:nginx wordpress:php-fpm84 mariadb:mariadbd'
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx staticsite \
        && R10_PAIRS="$R10_PAIRS staticsite:nginx"
    for pair in $R10_PAIRS; do
        c=${pair%%:*}; d=${pair#*:}
        P1=$(docker exec "$c" ps -o pid,comm 2>/dev/null | awk '$1==1{print $2}')
        [ "$P1" = "$d" ] || { ok=0; fail "R10 $c PID 1 is '$P1' (expected $d)"; }
    done
    R10_SEEN=$(printf '%s' "$R10_PAIRS" | tr ' ' '\n' | sed 's/:/ as PID1=/' | tr '\n' ',' | sed 's/,$//;s/,/, /g')
    [ $ok -eq 1 ] && pass "R10 PID 1 is the service daemon in every container ($R10_SEEN)"

    ok=1
    R19_LIST='nginx wordpress mariadb'
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx staticsite && R19_LIST="$R19_LIST staticsite"
    for c in $R19_LIST; do
        PATH1=$(docker inspect -f '{{.Path}}' "$c" 2>/dev/null)
        case "$(basename "$PATH1" 2>/dev/null)" in
            bash|sh|ash|zsh) ok=0; fail "R19 $c was started with a bare shell" "Path=$PATH1" ;;
        esac
        LNK=$(docker inspect -f '{{.HostConfig.Links}}' "$c" 2>/dev/null)
        case "$LNK" in
            ""|"[]"|"<no value>") : ;;
            *) ok=0; fail "R19 $c uses legacy links" "$LNK" ;;
        esac
        NM=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$c" 2>/dev/null)
        case "$NM" in
            host|none) ok=0; fail "R19 $c network mode is '$NM'" ;;
        esac
    done
    [ $ok -eq 1 ] && pass "R19 every container starts a real daemon, no links, on a project network"

    SSL_LINES=$(docker exec nginx nginx -T 2>/dev/null | grep -E '^[[:space:]]*ssl_protocols' | sed 's/^[[:space:]]*//;s/;[[:space:]]*$//')
    if [ -z "$SSL_LINES" ]; then
        fail "R21 no ssl_protocols anywhere in nginx's effective config"
    else
        SRV_POLICY=$(docker exec nginx nginx -T 2>/dev/null \
            | awk '/^[[:space:]]*server[[:space:]]*\{/{inserver=1} inserver && /ssl_protocols/{sub(/^[[:space:]]*/,"");sub(/;[[:space:]]*$/,"");print;exit}')
        case "$SRV_POLICY" in
            *TLSv1.2*TLSv1.3*|*TLSv1.3*TLSv1.2*)
                if printf '%s' "$SRV_POLICY" | grep -qE 'SSLv|TLSv1(\.[01])?([^.0-9]|$)'; then
                    fail "R21 the TLS server block allows an obsolete protocol" "$SRV_POLICY"
                else
                    pass "R21 nginx's effective server policy is '$SRV_POLICY'"
                fi ;;
            "") fail "R21 could not read the server block's ssl_protocols" ;;
            *)  fail "R21 server block policy is not TLSv1.2/1.3" "$SRV_POLICY" ;;
        esac
        STALE=$(printf '%s\n' "$SSL_LINES" | grep -E 'SSLv|TLSv1(\.[01])?([^.0-9]|$)' || true)
        [ -n "$STALE" ] && warn "R21 an inherited ssl_protocols still lists an obsolete protocol (overridden by the server block, but visible to \`nginx -T\`): $STALE"
    fi

    ok=1
    docker exec wordpress sh -c 'command -v nginx' >/dev/null 2>&1 && { ok=0; fail "R11 nginx binary present in wordpress container"; }
    docker exec mariadb  sh -c 'command -v nginx' >/dev/null 2>&1 && { ok=0; fail "R11 nginx binary present in mariadb container"; }
    docker exec nginx    sh -c 'command -v php-fpm84 || command -v mariadbd' >/dev/null 2>&1 && { ok=0; fail "R11 app daemons present in nginx container"; }
    [ $ok -eq 1 ] && pass "R11 strict service isolation (wordpress & mariadb ship no nginx, nginx ships no app daemons)"

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

    ok=1
    for pair in "inception_db_data:/home/$LOGIN/data/mariadb" "inception_wp_data:/home/$LOGIN/data/wordpress"; do
        v=${pair%%:*}; d=${pair#*:}
        DEV=$(docker volume inspect --format '{{index .Options "device"}}' "$v" 2>/dev/null)
        [ "$DEV" = "$d" ] || { ok=0; fail "R13 volume $v device is '$DEV' (expected $d)"; }
    done
    [ -f "/home/$LOGIN/data/wordpress/wp-config.php" ] || { ok=0; fail "R13 WordPress files not visible in /home/$LOGIN/data/wordpress"; }
    [ -d "/home/$LOGIN/data/mariadb" ] || { ok=0; fail "R13 /home/$LOGIN/data/mariadb missing on host"; }
    docker exec mariadb test -d /var/lib/mysql/mysql || { ok=0; fail "R13 MariaDB datadir empty in db_data volume"; }
    [ $ok -eq 1 ] && pass "R13 named volumes persist site + DB under /home/$LOGIN/data"

    ok=1
    docker exec mariadb   test -f /run/secrets/db_root_password || { ok=0; fail "R14 db_root_password secret missing in mariadb"; }
    docker exec wordpress test -f /run/secrets/credentials      || { ok=0; fail "R14 credentials secret missing in wordpress"; }
    docker exec nginx     test -f /run/secrets/server_key       || { ok=0; fail "R14 server_key secret missing in nginx"; }
    ENVLEAK=$(docker inspect nginx wordpress mariadb --format '{{.Name}} {{.Config.Env}}' | grep -iE 'PASS|SECRET|TOKEN' || true)
    [ -n "$ENVLEAK" ] && { ok=0; fail "R14 password-like environment variable exposed" "$ENVLEAK"; }
    [ $ok -eq 1 ] && pass "R14 credentials delivered via Docker secrets only — none in container env"

    POL=$(docker inspect nginx wordpress mariadb --format '{{.HostConfig.RestartPolicy.Name}}' | sort -u)
    if [ "$POL" = "unless-stopped" ] || [ "$POL" = "on-failure" ] || [ "$POL" = "always" ]; then
        pass "R15 restart policy '$POL' active on all containers"
    else
        fail "R15 inconsistent/missing restart policy" "$POL"
    fi

    NT=$(docker exec mariadb sh -c 'MYSQL_PWD="$(cat /run/secrets/db_password)" mariadb -u "$MYSQL_USER" "$MYSQL_DATABASE" -N -e "SHOW TABLES LIKE \"wp_%\";"' 2>/dev/null | wc -l)
    if [ "$NT" -ge 10 ]; then
        pass "R16 WordPress schema present in MariaDB ($NT wp_* tables)"
    else
        fail "R16 WordPress tables missing (found $NT)"
    fi

    ok=1
    for img in nginx:inception wordpress:inception mariadb:inception; do
        docker image history --no-trunc "$img" 2>/dev/null | grep -q 'entrypoint.sh' \
            || { ok=0; fail "R17 $img does not look like a local build of this repo"; }
    done
    [ $ok -eq 1 ] && pass "R17 all three images are local builds of this repository"

    ok=1
    docker exec wordpress nc -z mariadb 3306   2>/dev/null || { ok=0; fail "R18 wordpress cannot reach mariadb:3306"; }
    docker exec nginx     nc -z wordpress 9000 2>/dev/null || { ok=0; fail "R18 nginx cannot reach wordpress:9000"; }
    [ $ok -eq 1 ] && pass "R18 service-name DNS + reachability across the docker network"

    ok=1
    docker exec nginx nginx -T 2>/dev/null \
        | grep -qE 'fastcgi_pass[[:space:]]+(wordpress:9000|\$upstream_wordpress)' \
        || { ok=0; fail "R22 nginx does not fastcgi_pass to wordpress:9000"; }
    docker exec nginx nginx -T 2>/dev/null | grep -qE 'set[[:space:]]+\$upstream_wordpress[[:space:]]+wordpress:9000' \
        || docker exec nginx nginx -T 2>/dev/null | grep -qE 'fastcgi_pass[[:space:]]+wordpress:9000' \
        || { ok=0; fail "R22 the fastcgi upstream variable does not resolve to wordpress:9000"; }
    docker exec wordpress grep -qE "DB_HOST'?,?[[:space:]]*'?mariadb" /var/www/html/wp-config.php 2>/dev/null \
        || { ok=0; fail "R22 wp-config.php does not point DB_HOST at mariadb"; }
    docker exec wordpress sh -c "grep -rhE '^listen[[:space:]]*=' /etc/php*/php-fpm.d/*.conf 2>/dev/null" \
        | grep -q '9000' || { ok=0; fail "R22 php-fpm does not listen on 9000"; }
    docker exec mariadb sh -c 'nc -z 127.0.0.1 3306' 2>/dev/null \
        || { ok=0; fail "R22 mariadb is not listening on 3306 inside its container"; }
    [ $ok -eq 1 ] && pass "R22 www→nginx:443, nginx→wordpress:9000, wordpress→mariadb:3306 as configured"

    ok=1
    vols_of() { docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}:{{.Destination}} {{end}}{{end}}' "$1" 2>/dev/null; }
    MDB_V=$(vols_of mariadb); WP_V=$(vols_of wordpress); NGX_V=$(vols_of nginx)
    printf '%s' "$MDB_V" | grep -q 'db_data:/var/lib/mysql' \
        || { ok=0; fail "R23 mariadb does not mount the db volume at /var/lib/mysql" "$MDB_V"; }
    [ "$(printf '%s' "$MDB_V" | wc -w)" = "1" ] \
        || { ok=0; fail "R23 mariadb must mount exactly one volume" "$MDB_V"; }
    printf '%s' "$WP_V" | grep -q 'wp_data:/var/www/html' \
        || { ok=0; fail "R23 wordpress does not mount the site volume at /var/www/html" "$WP_V"; }
    printf '%s' "$WP_V" | grep -q 'db_data' \
        && { ok=0; fail "R23 wordpress must not mount the database volume" "$WP_V"; }
    printf '%s' "$NGX_V" | grep -q 'db_data' \
        && { ok=0; fail "R23 nginx must not mount the database volume" "$NGX_V"; }
    printf '%s' "$NGX_V" | grep -q 'wp_data:/var/www/html' \
        || warn "R23 nginx does not share the site volume — static assets may be served from a stale copy"
    [ $ok -eq 1 ] && pass "R23 db volume only in mariadb; site volume in wordpress (and nginx for static files)"

    ok=1; SHELLS=""
    for c in $(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^(nginx|wordpress|mariadb|redis|ftp|staticsite|adminer|dbbackup)$'); do
        S=$(docker exec "$c" sh -c 'printf "%s" "$(readlink -f /bin/sh)"; v=$(sh --version 2>/dev/null | head -1); [ -z "$v" ] || printf " (%s)" "$v"' 2>/dev/null)
        [ -n "$S" ] || { ok=0; fail "R24 /bin/sh does not answer in $c"; continue; }
        SHELLS="${SHELLS}${S}
"
    done
    DISTINCT=$(printf '%s' "$SHELLS" | sort -u | grep -c .)
    if [ "$DISTINCT" -gt 1 ]; then
        ok=0; fail "R24 the containers do not agree on /bin/sh" "$(printf '%s' "$SHELLS" | sort -u | tr '\n' ';')"
    fi
    [ $ok -eq 1 ] && pass "R24 every container runs its scripts under one shell: $(printf '%s' "$SHELLS" | head -1)"
fi

section "[E] Evaluation sheet (per-service walkthrough)"
if [ $RUNNING -eq 0 ]; then
    skip "E** stack not running"
else
    WPX="docker exec wordpress wp --allow-root --path=/var/www/html"

    ok=1
    for svc in wordpress mariadb; do
        DF="srcs/requirements/$svc/Dockerfile"
        [ -s "$DF" ] || { ok=0; fail "E01 $DF missing or empty"; continue; }
        if grep -vE '^[[:space:]]*#' "$DF" | grep -qiE '(apk add|apt-get install|yum install)[^&|]*[[:space:]]nginx([[:space:]]|$)|^[[:space:]]*(CMD|ENTRYPOINT).*nginx'; then
            ok=0; fail "E02 $DF installs or runs nginx"
        fi
    done
    [ $ok -eq 1 ] && pass "E01/E02 wordpress and mariadb have their own Dockerfile, neither installs nginx"

    CPS=$(docker compose -f "$COMPOSE_FILE" ps --format '{{.Name}} {{.State}}' 2>/dev/null)
    ok=1
    for c in nginx wordpress mariadb; do
        printf '%s\n' "$CPS" | grep -qE "^$c +running" || { ok=0; fail "E03 'docker compose ps' does not show $c running"; }
    done
    [ $ok -eq 1 ] && pass "E03 docker compose ps shows nginx, wordpress and mariadb running"

    ok=1
    for v in $(docker volume ls -q 2>/dev/null | grep -E 'wp_data|db_data'); do
        DEV=$(docker volume inspect --format '{{index .Options "device"}}' "$v" 2>/dev/null)
        case "$DEV" in
            /home/$LOGIN/data/*) : ;;
            *) ok=0; fail "E04 volume $v device is '$DEV', not under /home/$LOGIN/data/" ;;
        esac
    done
    [ $ok -eq 1 ] && pass "E04 docker volume inspect shows /home/$LOGIN/data/ for both volumes"

    ADMIN_USER=$(sed -n 's/^WP_ADMIN_USER=//p' srcs/.env | head -1)
    ADMIN_PW=$(sed -n 1p secrets/credentials.txt 2>/dev/null)
    if [ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PW" ]; then
        JAR=$(mktemp)
        curl -ks -c "$JAR" --max-time 20 "https://${DOMAIN}/wp-login.php" -o /dev/null

        LOGIN_HDR=$(curl -ks -b "$JAR" -c "$JAR" -D - -o /dev/null --max-time 30 \
            --data-urlencode "log=${ADMIN_USER}" \
            --data-urlencode "pwd=${ADMIN_PW}" \
            --data-urlencode "wp-submit=Log In" \
            --data-urlencode "redirect_to=https://${DOMAIN}/wp-admin/" \
            --data-urlencode "testcookie=1" \
            "https://${DOMAIN}/wp-login.php")
        LOGIN_CODE=$(printf '%s' "$LOGIN_HDR" | awk 'tolower($1) ~ /^http/ { c=$2 } END { print c }')
        HAS_COOKIE=$(grep -c 'wordpress_logged_in' "$JAR" 2> /dev/null || echo 0)

        if [ "${HAS_COOKIE:-0}" -lt 1 ]; then
            PW_OK=$(docker exec -e CPW="$ADMIN_PW" -e CU="$ADMIN_USER" wordpress php -r \
                'require "/var/www/html/wp-load.php";
                 $u = get_user_by("login", getenv("CU"));
                 echo ($u && wp_check_password(getenv("CPW"), $u->user_pass, $u->ID)) ? "yes" : "no";' \
                2> /dev/null)
            fail "E05 administrator sign-in was rejected" \
                 "POST wp-login.php -> HTTP ${LOGIN_CODE:-none}, no wordpress_logged_in cookie; stored password matches secrets/credentials.txt: ${PW_OK:-unknown}"
        else
            DASH=$(curl -ks -b "$JAR" --max-time 60 -w '\n%{http_code}' "https://${DOMAIN}/wp-admin/")
            DASH_CODE=$(printf '%s' "$DASH" | tail -n1)
            if [ "$DASH_CODE" = "200" ] && printf '%s' "$DASH" | grep -qi 'dashboard\|wp-admin-bar\|adminmenu'; then
                pass "E05 administrator '$ADMIN_USER' signs in over HTTPS and reaches the dashboard"
            else
                fail "E05 signed in, but /wp-admin/ did not render the dashboard" \
                     "GET /wp-admin/ -> HTTP ${DASH_CODE:-none}"
            fi
        fi
        rm -f "$JAR"
    else
        warn "E05 could not read admin credentials (run make setup)"
    fi

    POST_ID=$($WPX post list --post_type=post --post_status=publish --posts_per_page=1 --field=ID 2>/dev/null | head -1)
    WPUSER=$(sed -n 's/^WP_USER=//p' srcs/.env | head -1)
    if [ -n "$POST_ID" ] && [ -n "$WPUSER" ]; then
        UID_=$($WPX user get "$WPUSER" --field=ID 2>/dev/null)
        STAMP="compliance-comment-$$"
        CID=$($WPX comment create --comment_post_ID="$POST_ID" --comment_content="$STAMP" \
                --user_id="${UID_:-0}" --comment_approved=1 --porcelain 2>/dev/null)
        PLINK=$($WPX post get "$POST_ID" --field=url 2>/dev/null)
        : "${PLINK:=https://${DOMAIN}/?p=${POST_ID}}"
        if [ -n "$CID" ] && curl -ksL --max-time 25 "$PLINK" | grep -qF "$STAMP"; then
            pass "E06 user '$WPUSER' can comment, and the comment appears on the site"
        else
            fail "E06 comment by '$WPUSER' did not appear at $PLINK" "comment id=${CID:-none}"
        fi
        [ -n "$CID" ] && $WPX comment delete "$CID" --force > /dev/null 2>&1
    else
        warn "E06 no published post or WP_USER to comment with"
    fi

    PAGE_ID=$($WPX post list --post_type=page --post_status=publish --posts_per_page=1 --field=ID 2>/dev/null | head -1)
    if [ -n "$PAGE_ID" ]; then
        OLD=$($WPX post get "$PAGE_ID" --field=content 2>/dev/null)
        MARK="compliance-edit-$$"
        $WPX post update "$PAGE_ID" --post_content="${OLD}
<p>${MARK}</p>" > /dev/null 2>&1
        LINK=$($WPX post get "$PAGE_ID" --field=url 2>/dev/null)
        if curl -ks --max-time 20 "$LINK" | grep -qF "$MARK"; then
            pass "E07 a page edit is visible on the website"
        else
            fail "E07 a page edit did not appear at $LINK"
        fi
        printf '%s' "$OLD" | $WPX post update "$PAGE_ID" --post_content=- > /dev/null 2>&1
    else
        warn "E07 no published page to edit"
    fi

    DBUSER=$(sed -n 's/^MYSQL_USER=//p' srcs/.env | head -1)
    DBNAME=$(sed -n 's/^MYSQL_DATABASE=//p' srcs/.env | head -1)
    ROWS=$(printf 'SELECT COUNT(*) FROM %s;\n' "${PFX:-wp_}posts" \
        | docker exec -i mariadb sh -c 'exec mariadb -u '"$DBUSER"' -p"$(cat /run/secrets/db_password)" -N -B '"$DBNAME" 2>/dev/null)
    TBLS=$(printf 'SHOW TABLES;\n' \
        | docker exec -i mariadb sh -c 'exec mariadb -u '"$DBUSER"' -p"$(cat /run/secrets/db_password)" -N -B '"$DBNAME" 2>/dev/null | grep -c .)
    if [ "${TBLS:-0}" -gt 0 ] 2>/dev/null && [ "${ROWS:-0}" -gt 0 ] 2>/dev/null; then
        pass "E08 database login works as '$DBUSER'; $DBNAME holds $TBLS tables and $ROWS posts"
    else
        fail "E08 could not log into the database or it is empty" "tables=${TBLS:-0} posts=${ROWS:-0}"
    fi
fi

section "[B] Bonus"
if [ $RUNNING -eq 0 ]; then
    skip "B** stack not running"
else
    has_container() { docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"; }

    if has_container redis; then
        ok=1
        docker exec redis redis-cli ping 2>/dev/null | grep -qi PONG \
            || { ok=0; fail "B01 redis does not answer PING"; }
        docker exec wordpress grep -q 'WP_REDIS_HOST' /var/www/html/wp-config.php 2>/dev/null \
            || { ok=0; fail "B01 wp-config.php does not define WP_REDIS_HOST — WordPress is not using the cache"; }
        docker exec wordpress wp --allow-root --path=/var/www/html plugin list --status=active --field=name 2>/dev/null \
            | grep -qi redis || { ok=0; fail "B01 no active redis cache plugin in WordPress"; }
        [ $ok -eq 1 ] && pass "B01 redis answers and WordPress is configured to use it"
    else
        skip "B01 redis cache not implemented"
    fi

    if has_container ftp || has_container vsftpd; then
        FTPC=$(docker ps --format '{{.Names}}' | grep -E '^(ftp|vsftpd)$' | head -1)
        ok=1
        docker exec "$FTPC" sh -c 'nc -z 127.0.0.1 21' 2>/dev/null \
            || { ok=0; fail "B02 $FTPC is not listening on port 21"; }
        docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$FTPC" 2>/dev/null \
            | grep -q 'wp_data' || { ok=0; fail "B02 $FTPC does not mount the WordPress site volume"; }
        [ $ok -eq 1 ] && pass "B02 $FTPC listens on 21 and serves the WordPress volume"
    else
        skip "B02 FTP server not implemented"
    fi

    if has_container staticsite; then
        ok=1
        SPORT=$(docker ps --format '{{.Names}} {{.Ports}}' | awk '/^staticsite/{print}' | grep -oE '0\.0\.0\.0:[0-9]+' | cut -d: -f2 | head -1)
        : "${SPORT:=8090}"
        [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://${DOMAIN}:${SPORT}/")" = "200" ] \
            || { ok=0; fail "B03 static site does not answer on port $SPORT"; }
        PHPSRC=$(grep -rlE '<\?php' srcs/requirements/bonus/ 2>/dev/null || true)
        [ -n "$PHPSRC" ] && { ok=0; fail "B03 static site contains PHP" "$PHPSRC"; }
        docker exec staticsite sh -c 'command -v php' >/dev/null 2>&1 \
            && { ok=0; fail "B03 the static site image ships a PHP interpreter"; }
        [ $ok -eq 1 ] && pass "B03 static site served on $SPORT, contains no PHP"
    else
        skip "B03 static website not implemented"
    fi

    if has_container adminer; then
        APORT=$(docker ps --format '{{.Names}} {{.Ports}}' | awk '/^adminer/{print}' | grep -oE '0\.0\.0\.0:[0-9]+' | cut -d: -f2 | head -1)
        if [ -n "$APORT" ] && curl -s --max-time 8 "http://127.0.0.1:${APORT}/" | grep -qi adminer; then
            pass "B04 Adminer answers on port $APORT"
        else
            fail "B04 adminer container is running but does not serve Adminer"
        fi
    else
        skip "B04 Adminer not implemented"
    fi

    if has_container dbbackup; then
        ok=1
        LATEST=$(docker exec dbbackup sh -c 'ls -t /backups/*.sql.gz 2>/dev/null | head -1' 2>/dev/null)
        if [ -z "$LATEST" ]; then
            ok=0; fail "B05 dbbackup is running but has produced no backup"
        else
            docker exec dbbackup gzip -t "$LATEST" 2>/dev/null \
                || { ok=0; fail "B05 the latest backup is not a valid gzip archive" "$LATEST"; }
            SIZE=$(docker exec dbbackup sh -c "wc -c < '$LATEST'" 2>/dev/null | tr -d ' ')
            [ "${SIZE:-0}" -gt 1000 ] 2>/dev/null \
                || { ok=0; fail "B05 the latest backup is suspiciously small (${SIZE:-0} bytes)"; }
            docker exec dbbackup sh -c "gzip -dc '$LATEST' | grep -qi 'CREATE TABLE'" 2>/dev/null \
                || { ok=0; fail "B05 the backup contains no CREATE TABLE — it is not a real dump"; }
        fi
        docker exec dbbackup test -x /usr/local/bin/restore.sh 2>/dev/null \
            || { ok=0; fail "B05 no restore script in the backup container"; }
        [ $ok -eq 1 ] && pass "B05 dbbackup: verified dump present ($(basename "$LATEST"), ${SIZE} bytes) and a restore path exists"
    else
        EXTRA=$(docker ps --format '{{.Names}}' 2>/dev/null \
            | grep -vxE 'nginx|wordpress|mariadb|redis|ftp|vsftpd|staticsite|adminer' | tr '\n' ' ')
        if [ -n "$(printf '%s' "$EXTRA" | tr -d '[:space:]')" ]; then
            pass "B05 additional service(s) present: $EXTRA (be ready to justify the choice)"
        else
            skip "B05 no extra service of your choice"
        fi
    fi
fi

section "[D] Deep (crash-restart & persistence)"

if [ $DEEP -eq 0 ]; then
    skip "D** run with --deep (or 'make test-deep') to exercise crash-restart and persistence"
elif [ $RUNNING -eq 0 ]; then
    skip "D** stack not running"
else
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

    i=0
    while [ $i -lt 45 ]; do
        CODE=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 2 "https://$DOMAIN/" 2>/dev/null || echo 000)
        [ "$CODE" = "200" ] && break
        sleep 2; i=$((i+1))
    done

    if [ "$(id -u)" = "0" ] || sudo -n true 2>/dev/null; then
        SUDO=""; [ "$(id -u)" = "0" ] || SUDO="sudo -n"
        ok=1
        for c in nginx wordpress mariadb; do
            BEFORE=$(docker inspect -f '{{.RestartCount}}' "$c" 2>/dev/null || echo 0)
            HOSTPID=$(docker inspect -f '{{.State.Pid}}' "$c" 2>/dev/null || echo 0)
            if [ "$HOSTPID" = "0" ]; then
                ok=0; fail "D03 could not read host pid of $c"; continue
            fi
            $SUDO kill -9 "$HOSTPID" 2>/dev/null || true
            i=0; back=0
            while [ $i -lt 30 ]; do
                sleep 1
                ST=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo gone)
                AFTER=$(docker inspect -f '{{.RestartCount}}' "$c" 2>/dev/null || echo "$BEFORE")
                if [ "$ST" = "running" ] && [ "$AFTER" -gt "$BEFORE" ]; then back=1; break; fi
                i=$((i+1))
            done
            [ $back -eq 1 ] || { ok=0; fail "D03 $c did not restart after SIGKILL (RestartCount stayed $BEFORE)"; }
        done
        i=0
        while [ $i -lt 45 ]; do
            CODE=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 2 "https://$DOMAIN/" 2>/dev/null || echo 000)
            [ "$CODE" = "200" ] && break
            sleep 2; i=$((i+1))
        done
        [ $ok -eq 1 ] && pass "D03 all containers restart after a real crash (SIGKILL), RestartCount incremented"
    else
        warn "D03 real-crash test needs root to signal the container's init — run: sudo -E sh tests/compliance.sh --deep"
    fi

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

printf "\n${BLU}══ Summary ══${RST}  ${GRN}%d passed${RST}  ${RED}%d failed${RST}  ${YLW}%d warnings${RST}  ${DIM}%d skipped${RST}\n" "$PASS" "$FAIL" "$WARN" "$SKIP"
[ $FAIL -gt 254 ] && exit 254
exit $FAIL
