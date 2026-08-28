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
# The three above are the mandatory services, and the rules that say "exactly
# three" must keep using them. The anti-hack rules are different: they apply to
# every container the project ships, bonus included, so they scan these instead.
ALL_DOCKERFILES=$(ls srcs/requirements/*/Dockerfile srcs/requirements/*/*/Dockerfile 2>/dev/null)
ALL_ENTRYPOINTS=$(ls srcs/requirements/*/tools/*.sh srcs/requirements/*/*/tools/*.sh 2>/dev/null)
# S18's rule is about the process a container STARTS, so it looks only at
# entrypoints. ALL_ENTRYPOINTS above stays wider on purpose: the anti-hack
# scan must read every script that ships, helper scripts included.
ENTRYPOINT_FILES=$(ls srcs/requirements/*/tools/entrypoint.sh srcs/requirements/*/*/tools/entrypoint.sh 2>/dev/null)

printf "${BLU}══ Inception compliance suite ══${RST}  login=%s domain=%s\n" "$LOGIN" "$DOMAIN"

# ─────────────────────────────────────────────────────────────────────
section "[S] Structure & Makefile"
# ─────────────────────────────────────────────────────────────────────

# S01 required layout — the tree the subject shows in its `ls -alR`
#
#   .
#   |-- Makefile
#   |-- secrets/   credentials.txt, db_password.txt, db_root_password.txt
#   `-- srcs/      docker-compose.yml, .env, requirements/
#                  requirements/{nginx,wordpress,mariadb}/
#                      Dockerfile, .dockerignore, conf/, tools/
ok=1
for f in Makefile "$COMPOSE_FILE" srcs/.env \
         secrets/db_password.txt secrets/db_root_password.txt secrets/credentials.txt; do
    [ -f "$f" ] || { ok=0; fail "S01 missing: $f"; }
done
for d in secrets srcs srcs/requirements; do
    [ -d "$d" ] || { ok=0; fail "S01 missing directory: $d/"; }
done
# .env belongs in srcs/. One at the repo root is the common mistake: compose
# picks it up from either place, so the stack still works and nothing else here
# would notice.
[ -f .env ] && { ok=0; fail "S01 .env must live in srcs/, not at the repository root"; }
for s in nginx wordpress mariadb; do
    [ -f "srcs/requirements/$s/Dockerfile" ]          || { ok=0; fail "S01 missing Dockerfile for $s"; }
    [ -f "srcs/requirements/$s/tools/entrypoint.sh" ] || { ok=0; fail "S01 missing entrypoint for $s"; }
    [ -d "srcs/requirements/$s/conf" ]                || { ok=0; fail "S01 missing conf/ for $s"; }
    [ -d "srcs/requirements/$s/tools" ]               || { ok=0; fail "S01 missing tools/ for $s"; }
    # The subject's tree lists a .dockerignore per service. A warning here is a
    # landmine that everyone learns to scroll past, so it is a verdict.
    [ -f "srcs/requirements/$s/.dockerignore" ] \
        || { ok=0; fail "S01 missing .dockerignore for $s (the subject's tree shows one)"; }
done
[ $ok -eq 1 ] && pass "S01 layout matches the subject's tree (Makefile, secrets/, srcs/requirements/<svc>/{Dockerfile,conf,tools})"

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

# S25 README.md contains every section the subject mandates
#
# S02 only checks the file exists and the first line is right. The subject lists
# specific sections and four specific comparisons, and a missing one is a
# grading failure, so each is checked by name.
ok=1
if [ -f README.md ]; then
    # The first line must be italic — one asterisk each side. Bold (**...**) is
    # a different thing and does not satisfy "italicized".
    FIRST=$(head -1 README.md)
    printf '%s' "$FIRST" | grep -qE '^\*[^*].*\*$' \
        || { ok=0; fail "S25 README first line is not italicised with single asterisks" "$FIRST"; }
    printf '%s' "$FIRST" | grep -qF "$LOGIN" \
        || { ok=0; fail "S25 README first line does not name the login '$LOGIN'" "$FIRST"; }
    # Required sections, matched as headings so a passing mention in prose does
    # not count as having the section.
    for sect in "Description" "Instructions" "Resources" "Project description"; do
        grep -qiE "^#{1,4}[[:space:]]+.*${sect}" README.md \
            || { ok=0; fail "S25 README has no '$sect' section"; }
    done
    # The Resources section must also cover how AI was used.
    grep -qiE '^#{1,4}[[:space:]]+.*(AI|artificial intelligence)' README.md \
        || grep -qiE '\b(AI was used|use of AI|AI usage)\b' README.md \
        || { ok=0; fail "S25 README does not describe how AI was used (required in Resources)"; }
    # The four mandated comparisons.
    for cmp in "Virtual Machines vs Docker" "Secrets vs Environment Variables" \
               "Docker Network vs Host Network" "Docker Volumes vs Bind Mounts"; do
        grep -qiF "$cmp" README.md \
            || { ok=0; fail "S25 README is missing the comparison '$cmp'"; }
    done
fi
[ $ok -eq 1 ] && pass "S25 README has the mandated sections, AI usage and all four comparisons"

# S26 USER_DOC.md and DEV_DOC.md cover the points the subject lists
#
# These are topics rather than fixed headings, so each is matched on the
# vocabulary it cannot plausibly be written without. The intent is to catch a
# missing SUBJECT, not to grade the prose.
ok=1
check_topic() { # file, human name, regex
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
# Two forms, and only the explicit one used to be checked. `FROM alpine` with no
# tag IS `FROM alpine:latest` — Docker resolves it that way — so an untagged
# base slips the rule while looking innocent. A digest (@sha256:...) is pinned
# and therefore fine.
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
#
# The subject's point is that a container is not a VM: PID 1 must BE the daemon,
# not a babysitter keeping an otherwise-empty container alive.
#
# Only unconditionally-infinite constructs are prohibited. A bounded wait such
# as `until <condition>; do sleep 1; done` — which the wordpress entrypoint uses
# to wait for MariaDB — is correct and must not be flagged, so `until` and small
# `sleep` values are deliberately not matched.
#
# Comments are stripped first: a file explaining why it does NOT use tail -f
# should not fail for saying so.
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

# S07 network rules
ok=1
grep -q '^networks:' "$COMPOSE_FILE" || { ok=0; fail "S07 top-level 'networks:' line missing"; }
grep -qE 'network_mode:[[:space:]]*host' "$COMPOSE_FILE" && { ok=0; fail "S07 network_mode: host is forbidden"; }
grep -qE '^\s+links:' "$COMPOSE_FILE" && { ok=0; fail "S07 links: is forbidden"; }
# Every service must actually join a network, not just have one declared at the
# top of the file. A service that omits `networks:` silently lands on compose's
# default bridge instead of the project's own.
SVC_BLOCK=$(awk '/^services:/,/^(volumes|networks):/' "$COMPOSE_FILE")
SVC_N=$(printf '%s\n' "$SVC_BLOCK" | grep -cE '^  [a-zA-Z0-9_-]+:[[:space:]]*$')
NET_N=$(printf '%s\n' "$SVC_BLOCK" | grep -cE '^    networks:')
[ "$SVC_N" = "$NET_N" ] || { ok=0; fail "S07 only $NET_N of $SVC_N services declare 'networks:'"; }
# --link is the legacy form of the same prohibition, and lives outside compose.
# Scope: how containers are actually started — the Makefile and srcs/. Not
# tests/, which necessarily contains the forbidden strings in order to look for
# them, and would otherwise flag itself.
LINKHITS=$(grep -rnE '(^|[[:space:]])--link([[:space:]]|=)|^[[:space:]]*external_links:' \
    Makefile srcs 2>/dev/null | grep -v '^Binary' || true)
[ -z "$LINKHITS" ] || { ok=0; fail "S07 legacy --link / external_links found" "$LINKHITS"; }
[ $ok -eq 1 ] && pass "S07 networks: present, all $SVC_N services joined, no host networking, no links"

# S08 restart policy on every service
N=$(grep -c 'restart:' "$COMPOSE_FILE")
if [ "$N" -ge 3 ]; then
    pass "S08 restart policy declared on all $N services ($(grep 'restart:' "$COMPOSE_FILE" | awk '{print $2}' | sort -u | tr '\n' ' '))"
else
    fail "S08 restart policy missing on some services (found $N, need one per service)"
fi

# S09 image name == service name
ok=1
for s in nginx wordpress mariadb; do
    svc_block "$s" | grep -q "image: *$s:" || { ok=0; fail "S09 image name for service '$s' must be '$s:<tag>'"; }
done
[ $ok -eq 1 ] && pass "S09 each image is named after its service (nginx, wordpress, mariadb)"

# S10 only nginx publishes ports among the mandatory services, and only 443
# (bonus services are explicitly allowed their own ports by the subject —
# scoped to nginx's own block so a bonus port never trips this check)
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
[ $ok -eq 1 ] && pass "S11 named volumes (db_data, wp_data and any bonus volume) all under /home/$LOGIN/data, no service bind mounts"

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

# S13 no credentials in Dockerfiles
# The subject bans passwords, and the failure clause covers "any credentials,
# API keys, or passwords", so look for all three — and in every Dockerfile the
# project ships, bonus included. ARG counts too: build args end up in the image
# history and are readable with `docker history`.
S13RE='(pass(wd|word)?|secret|api[_-]?key|token|credential)[[:space:]]*='
S13RE="$S13RE"'|^[[:space:]]*(ENV|ARG)[[:space:]]+[A-Z_]*(PASS|SECRET|TOKEN|KEY|CRED)'
S13HITS=$(grep -hinE "$S13RE" $ALL_DOCKERFILES 2>/dev/null \
    | grep -viE '_FILE|/run/secrets|\$\{|example|placeholder' || true)
if [ -n "$S13HITS" ]; then
    fail "S13 credential-like content in a Dockerfile" "$S13HITS"
else
    pass "S13 no passwords, API keys or tokens in any Dockerfile"
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

# S24 the actual live secret values appear nowhere they could be published
#
# S14 and S15 pattern-match for things that LOOK like credentials, which is
# guesswork in both directions: it misses a password that happens not to match,
# and it fires on harmless lines. This takes the real values out of secrets/ and
# srcs/.env and searches for those exact strings — no false positives, and no
# way for a genuinely published credential to slip through.
#
# Four places a value could end up published: tracked files, git history, image
# layers (build args survive in `docker history`), and container environment.
ok=1
SECRET_VALUES=""
for f in secrets/db_password.txt secrets/db_root_password.txt secrets/credentials.txt \
         secrets/ftp_password.txt; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
        # Skip anything too short to be a real secret; matching those would
        # produce noise, not findings.
        [ ${#line} -ge 8 ] && SECRET_VALUES="$SECRET_VALUES
$line"
    done < "$f"
done
# Passwords set in .env count too, if any are kept there.
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
        # HEAD is what is published; the working tree is what is about to be.
        # A secret pasted into a tracked file and not yet committed must be
        # caught now, not after it is pushed.
        git grep -qF -- "$v" HEAD 2>/dev/null && echo "COMMITTED:$v"
        git ls-files -z 2>/dev/null | xargs -0 grep -lF -- "$v" 2>/dev/null | grep -q . \
            && echo "WORKTREE:$v"
        git log --all -p 2>/dev/null | grep -qF -- "$v" && echo "HISTORY:$v"
    done > /tmp/.s24hits 2>/dev/null
    HITS=$(cat /tmp/.s24hits 2>/dev/null | sed 's/\(:.\{0,3\}\).*/\1.../'); rm -f /tmp/.s24hits
    if [ -n "$HITS" ]; then
        # Never print the value itself — a test that leaks the secret into a log
        # or a screenshot has become the thing it was written to prevent.
        ok=0; fail "S24 a live secret value is published" "$HITS"
    fi
    # S24 runs in the static section, before RUNNING is set, so decide for
    # itself whether there is a live stack to inspect rather than reading a
    # variable that does not exist yet.
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
for e in $ENTRYPOINT_FILES; do
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

# S20 the domain is <login>.42.fr and points at a local address
#
# Three separate things, and the old version only looked at the last one — with
# a grep of /etc/hosts, and only a warning if it failed:
#   a) the NAME. DOMAIN comes from srcs/.env, so nothing stopped it being
#      "foo.com": the check would then cheerfully confirm foo.com resolves.
#      The subject requires exactly <login>.42.fr.
#   b) it must actually RESOLVE. A line can sit in /etc/hosts and still not
#      resolve (malformed entry, nsswitch not consulting files), so ask the
#      resolver rather than reading the file.
#   c) it must point at a LOCAL address.
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

# S22 nginx pins TLSv1.2/1.3 in its configuration
# The runtime probe (R03) can only report what a client is able to offer, and a
# modern OpenSSL refuses to speak TLSv1.0/1.1 at all. This check reads the
# config directly, so a regression is caught even where the handshake cannot be
# attempted.
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

# S23 the container's start command is not a shell or a loop
#
# The subject names `bash` itself as a prohibited hacky patch: a container whose
# command is a bare shell stays alive doing nothing, which is exactly the
# "container as a VM" pattern it warns against.
#
# ONLY column-0 CMD/ENTRYPOINT instructions are the container's command. The
# indented `CMD` inside a HEALTHCHECK is a different thing entirely — mariadb's
# healthcheck legitimately runs `sh -c '... mariadb-admin ping ...'` and must not
# be mistaken for a shell entrypoint.
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
# compose can override the image's command; the same rules apply there.
OVERRIDE=$(grep -nE '^[[:space:]]+(command|entrypoint):' "$COMPOSE_FILE" || true)
if [ -n "$OVERRIDE" ]; then
    if printf '%s' "$OVERRIDE" | grep -qE '(bash|/bin/sh|[^a-z]sh)[[:space:]]*$' \
        || printf '%s' "$OVERRIDE" | grep -qE "$HACK_RE"; then
        ok=0; fail "S23 compose command/entrypoint override is a shell or a hack" "$OVERRIDE"
    fi
fi
[ $ok -eq 1 ] && pass "S23 no service starts a bare shell or a keep-alive loop as its command"

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
    #
    # The obvious form of this test — "the handshake did not succeed, therefore
    # the server rejected it" — does not work. Debian's OpenSSL sets
    # MinProtocol=TLSv1.2, so the client refuses to even offer TLSv1.0/1.1 and
    # fails locally with "no protocols available". That is indistinguishable
    # from a server refusal, and the check passed against a closed port.
    #
    # So: lift the client's floor with a throwaway OPENSSL_CONF, then classify
    # the outcome in three ways instead of two. A refusal only counts when the
    # SERVER said no — an alert, which reaches us as "tlsv1 alert protocol
    # version" / "wrong version number".
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
            : # the server rejected it, which is what the subject requires
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
    #
    # "Answered on 80" and "this project opened 80" are different claims, and
    # only the second is a compliance failure. Anything else on the machine
    # holding 80 is outside the infrastructure — but an evaluator sitting at
    # this VM still sees it, so it must be reported, not silently passed.
    R07CONT=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E ':80->' || true)
    R07ANSWERS=0
    curl -s -o /dev/null --max-time 3 "http://$DOMAIN/" 2>/dev/null && R07ANSWERS=1
    if [ -n "$R07CONT" ]; then
        fail "R07 a container of this project publishes port 80" "$R07CONT"
    elif [ "$R07ANSWERS" = "1" ]; then
        # ss only reveals the owning process to root; $NF would otherwise print
        # the peer-address column, which reads as a nonsense process name.
        OWNER=$(ss -ltnp 2>/dev/null | grep ':80 ' | grep -oE 'users:\(\("[^"]+"' | head -1 | sed 's/.*"\(.*\)"/\1/')
        warn "R07 something outside this project answers on port 80 ${OWNER:+($OWNER)} — no Inception container publishes it, but an evaluator will see it"
    else
        pass "R07 port 80 closed; nginx:443 is the only entrypoint"
    fi

    # R08 WordPress users: two users, one compliant administrator
    ULIST=$(docker exec wordpress wp --allow-root --path=/var/www/html user list --fields=user_login,roles --format=csv 2>/dev/null | tail -n +2)
    NUSERS=$(printf '%s\n' "$ULIST" | grep -c .)
    NADMIN=$(printf '%s\n' "$ULIST" | grep -c ',administrator')
    # Flatten to one line: with two administrators this holds a newline, which
    # cut the failure message off mid-name precisely when it was needed.
    ADMIN_LOGIN=$(printf '%s\n' "$ULIST" | grep ',administrator' | cut -d, -f1 | paste -sd, -)
    ok=1
    [ "$NUSERS" -eq 2 ] || { ok=0; fail "R08 expected 2 WordPress users, found $NUSERS"; }
    [ "$NADMIN" -eq 1 ] || { ok=0; fail "R08 expected exactly 1 administrator, found $NADMIN"; }
    case "$(printf %s "$ADMIN_LOGIN" | tr '[:upper:]' '[:lower:]')" in
        *admin*|"") ok=0; fail "R08 administrator login '$ADMIN_LOGIN' violates naming rule" ;;
    esac
    [ $ok -eq 1 ] && pass "R08 two WP users; administrator '$ADMIN_LOGIN' complies with naming rule"

    # R20 the same rule, read straight out of the database
    #
    # The subject says "in your WordPress database". R08 asks wp-cli, which is
    # convenient but is still WordPress reporting on itself. This asks MariaDB
    # directly, so a wp-cli misconfiguration — or a user created only through
    # the application layer — cannot hide the real state of the data.
    #
    # The role lives in wp_usermeta.wp_capabilities as a serialised PHP array,
    # e.g. a:1:{s:13:"administrator";b:1;}, so the administrator is found by
    # matching that string rather than by any column in wp_users.
    # SQL goes in on stdin, not through -e: the capabilities value contains
    # double quotes, and passing those through docker exec + sh -c + -e
    # mangles them into a query that silently matches nothing.
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
        # wp_capabilities is a serialised PHP array; 'administrator' appears in it
        # only for an administrator, so a plain LIKE is enough and avoids having to
        # quote the embedded double quotes through three layers of shell.
        DBADMINS=$(DBQ "SELECT u.user_login FROM ${PFX}users u JOIN ${PFX}usermeta m ON m.user_id=u.ID WHERE m.meta_key='${PFX}capabilities' AND m.meta_value LIKE '%administrator%';")
        NDBADM=$(printf '%s\n' "$DBADMINS" | grep -c .)
        DBADMINS=$(printf '%s\n' "$DBADMINS" | paste -sd, - )
        [ "$DBUSERS" = "2" ] || { ok=0; fail "R20 ${PFX}users holds $DBUSERS rows, expected 2"; }
        [ "$NDBADM" = "1" ] || { ok=0; fail "R20 expected exactly 1 administrator in the database, found $NDBADM" "$DBADMINS"; }
        case "$(printf %s "$DBADMINS" | tr '[:upper:]' '[:lower:]')" in
            *admin*|"") ok=0; fail "R20 administrator user_login '$DBADMINS' contains 'admin'" ;;
        esac
        # The rule is about the username, but a display name of "Admin" is the
        # first thing a defence will notice, so say something without failing.
        OTHER=$(DBQ "SELECT CONCAT(user_nicename,' ',display_name) FROM ${PFX}users WHERE user_login='${DBADMINS}';")
        case "$(printf %s "$OTHER" | tr '[:upper:]' '[:lower:]')" in
            *admin*) warn "R20 administrator's nicename/display name contains 'admin' ($OTHER) — the rule targets the username, but expect the question" ;;
        esac
        [ $ok -eq 1 ] && pass "R20 database itself holds 2 users, 1 administrator ('$DBADMINS'), name complies"
    fi

    # R09 an active theme exists (blank-site regression check)
    if docker exec wordpress wp --allow-root --path=/var/www/html theme list --status=active --field=name 2>/dev/null | grep -q .; then
        pass "R09 an active WordPress theme is installed"
    else
        fail "R09 no active theme — the site would render a blank page"
    fi

    # R10 real daemons run as PID 1
    ok=1
    R10_PAIRS='nginx:nginx wordpress:php-fpm84 mariadb:mariadbd'
    # A bonus container is still a container: PID 1 must be its daemon too.
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx staticsite \
        && R10_PAIRS="$R10_PAIRS staticsite:nginx"
    for pair in $R10_PAIRS; do
        c=${pair%%:*}; d=${pair#*:}
        P1=$(docker exec "$c" ps -o pid,comm 2>/dev/null | awk '$1==1{print $2}')
        [ "$P1" = "$d" ] || { ok=0; fail "R10 $c PID 1 is '$P1' (expected $d)"; }
    done
    # Name what was actually inspected, so the line cannot claim coverage it
    # does not have when a container is missing or a bonus one is added.
    R10_SEEN=$(printf '%s' "$R10_PAIRS" | tr ' ' '\n' | sed 's/:/ as PID1=/' | tr '\n' ',' | sed 's/,$//;s/,/, /g')
    [ $ok -eq 1 ] && pass "R10 PID 1 is the service daemon in every container ($R10_SEEN)"

    # R19 what Docker actually launched, and how it is networked
    # Static rules can be satisfied while the running container tells a
    # different story, so read it back from the daemon.
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

    # R21 the TLS policy nginx is actually running
    #
    # S22 reads the project's own conf file. That is not the whole config: the
    # base image ships /etc/nginx/nginx.conf, and Alpine's declares
    # "ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3" at http level. The server block
    # overrides it — which is why the handshake test passes — but a defence
    # running `nginx -T | grep ssl_protocols` sees TLSv1.1 and will ask about
    # it. `nginx -T` is the authoritative, fully-resolved config, so read that.
    SSL_LINES=$(docker exec nginx nginx -T 2>/dev/null | grep -E '^[[:space:]]*ssl_protocols' | sed 's/^[[:space:]]*//;s/;[[:space:]]*$//')
    if [ -z "$SSL_LINES" ]; then
        fail "R21 no ssl_protocols anywhere in nginx's effective config"
    else
        # The directive that applies to the TLS server is the one inside its
        # server block, i.e. the last one nginx resolves for that context.
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
        # Inherited defaults do not change behaviour here, but they are the
        # first thing a grep of the running config turns up.
        STALE=$(printf '%s\n' "$SSL_LINES" | grep -E 'SSLv|TLSv1(\.[01])?([^.0-9]|$)' || true)
        [ -n "$STALE" ] && warn "R21 an inherited ssl_protocols still lists an obsolete protocol (overridden by the server block, but visible to \`nginx -T\`): $STALE"
    fi

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

    # R22 the services are CONFIGURED for that wiring, not merely able to reach it
    #
    # R18 proves a socket answers on wordpress:9000 and mariadb:3306. It does not
    # prove nginx routes PHP there, or that WordPress talks to that database —
    # nginx could be serving from somewhere else entirely and R18 would still be
    # green. Read the configuration each service is actually running.
    ok=1
    # Either the literal upstream or the variable form used to force runtime
    # DNS re-resolution; both must point at wordpress:9000.
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
    # The application ports must stay inside the network: only 443 is published,
    # which R02 checks, but assert the sockets themselves are container-local.
    docker exec mariadb sh -c 'nc -z 127.0.0.1 3306' 2>/dev/null \
        || { ok=0; fail "R22 mariadb is not listening on 3306 inside its container"; }
    [ $ok -eq 1 ] && pass "R22 www→nginx:443, nginx→wordpress:9000, wordpress→mariadb:3306 as configured"

    # R23 volume topology: each container has the volume it should, and no other
    #
    # A container mounting a volume it has no business with is invisible to
    # every other check here: the stack works, ports are right, and the data
    # still ends up somewhere it should not be.
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
    # nginx serving the site's static files from the same volume is correct and
    # expected: it is the web server for those files, PHP is handled over
    # fastcgi. Only note its absence, which would mean assets are served from a
    # copy that can drift.
    printf '%s' "$NGX_V" | grep -q 'wp_data:/var/www/html' \
        || warn "R23 nginx does not share the site volume — static assets may be served from a stale copy"
    [ $ok -eq 1 ] && pass "R23 db volume only in mariadb; site volume in wordpress (and nginx for static files)"
fi

# ─────────────────────────────────────────────────────────────────────
section "[B] Bonus"
# ─────────────────────────────────────────────────────────────────────
# The bonus is optional, and it is only looked at if the mandatory part is
# perfect. So an absent bonus is reported as skipped, not failed — but a bonus
# that IS present has to work, because a half-built one is worse at defence
# than none at all.
if [ $RUNNING -eq 0 ]; then
    skip "B** stack not running"
else
    has_container() { docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"; }

    # B01 redis cache wired into WordPress
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

    # B02 FTP server pointing at the WordPress volume
    if has_container ftp || has_container vsftpd; then
        FTPC=$(docker ps --format '{{.Names}}' | grep -E '^(ftp|vsftpd)$' | head -1)
        ok=1
        docker exec "$FTPC" sh -c 'nc -z 127.0.0.1 21' 2>/dev/null \
            || { ok=0; fail "B02 $FTPC is not listening on port 21"; }
        # The point of the bonus is that it serves the SITE volume, not a copy.
        docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' "$FTPC" 2>/dev/null \
            | grep -q 'wp_data' || { ok=0; fail "B02 $FTPC does not mount the WordPress site volume"; }
        [ $ok -eq 1 ] && pass "B02 $FTPC listens on 21 and serves the WordPress volume"
    else
        skip "B02 FTP server not implemented"
    fi

    # B03 static site, in any language except PHP
    if has_container staticsite; then
        ok=1
        SPORT=$(docker ps --format '{{.Names}} {{.Ports}}' | awk '/^staticsite/{print}' | grep -oE '0\.0\.0\.0:[0-9]+' | cut -d: -f2 | head -1)
        : "${SPORT:=8090}"
        [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://${DOMAIN}:${SPORT}/")" = "200" ] \
            || { ok=0; fail "B03 static site does not answer on port $SPORT"; }
        # "except PHP" is the actual rule, so check the sources and the image.
        PHPSRC=$(grep -rlE '<\?php' srcs/requirements/bonus/ 2>/dev/null || true)
        [ -n "$PHPSRC" ] && { ok=0; fail "B03 static site contains PHP" "$PHPSRC"; }
        docker exec staticsite sh -c 'command -v php' >/dev/null 2>&1 \
            && { ok=0; fail "B03 the static site image ships a PHP interpreter"; }
        [ $ok -eq 1 ] && pass "B03 static site served on $SPORT, contains no PHP"
    else
        skip "B03 static website not implemented"
    fi

    # B04 Adminer
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

    # B05 a service of your choice — here, scheduled database backups
    #
    # "A container is running" is not evidence a backup service works; that is
    # exactly how backups are discovered to be broken on the day they are
    # needed. So: a dump must exist, be non-empty, and pass gzip's own integrity
    # check.
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
            # It must contain the WordPress schema, not just be a well-formed
            # empty dump.
            docker exec dbbackup sh -c "gzip -dc '$LATEST' | grep -qi 'CREATE TABLE'" 2>/dev/null \
                || { ok=0; fail "B05 the backup contains no CREATE TABLE — it is not a real dump"; }
        fi
        # The restore path is half the service; a backup you cannot restore is
        # not a backup.
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

    # D03 containers come back from a REAL crash
    #
    # D01 above kills PID 1 from inside the container, which only works because
    # the daemons handle SIGTERM: they shut down cleanly and exit 0. That proves
    # an unexpected exit is restarted, but it is not a crash.
    #
    # Two things that look like they would simulate one, and do not:
    #   docker exec <c> kill -9 1   the kernel refuses SIGKILL sent to PID 1
    #                               from inside its own PID namespace. No-op.
    #   docker kill <c>             goes through the Docker API, which records a
    #                               manual stop, so the restart policy is
    #                               deliberately skipped and the container stays
    #                               exited. Measured: the site went down and did
    #                               not come back.
    #
    # A real crash is SIGKILL to the container's init as seen from the HOST pid
    # namespace, which never touches the Docker API. RestartCount incrementing
    # is what proves the restart policy did the work, rather than an entrypoint
    # respawning something internally.
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
        # let the stack settle before the persistence test below
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
