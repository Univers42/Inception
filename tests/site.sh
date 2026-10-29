#!/bin/hellish
# shellcheck shell=sh
#
# tests/site.sh — the landing, Deeper, the blog and the wiki against the stack.
# Like tests/lab.sh, every request goes through the edge nginx over TLS,
# resolved to loopback, except the checks that look inside a container.
#
#   make test-site                # ~10 s, read-only
#
# What it pins: the bare / is WordPress's front page (the eval sheet opens it
# and expects the configured site) and links to the landing; the landing (bonus
# staticsite) answers at /dream/ and makes no third-party request; the blog is
# /blog/ and the old /journal/ redirects there; the wiki answers three levels
# deep with its table of contents and is searchable; the plugins run at the
# versions site/plugins.txt pins; the landing image ships no node and no PHP;
# diagrams are Mermaid; the guide series is published; the sign-in page is
# branded, takes the administrator from the secrets and is hardened; WordPress
# makes no third-party request and versions its assets by content; /deeper/
# is the staticsite's second app, prerendered and self-contained; a post has
# its on-this-page rail and every title is in sentence case.
set -u
cd "$(dirname "$0")/.." || exit 1
if [ -t 1 ]; then
    RED='\033[0;31m'; GRN='\033[0;32m'; BLU='\033[1;34m'; DIM='\033[2m'; RST='\033[0m'
else
    RED=''; GRN=''; BLU=''; DIM=''; RST=''
fi
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf "  ${GRN}✔${RST} %s\n" "$1"; }
fail() { FAIL=$((FAIL+1)); printf "  ${RED}✘${RST} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${DIM}%s${RST}\n" "$2"; }
section() { printf "\n${BLU}%s${RST}\n" "$1"; }

LOGIN=$(sed -n 's/^LOGIN[[:space:]]*=[[:space:]]*//p' Makefile | head -1)
DOMAIN=$(sed -n 's/^DOMAIN_NAME=//p' srcs/.env 2>/dev/null | head -1)
[ -n "$DOMAIN" ] || DOMAIN="$LOGIN.42.fr"
PORT="${HTTPS_PORT:-443}"
BASE="https://$DOMAIN:$PORT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
c() { curl -ks --max-time 15 --resolve "$DOMAIN:$PORT:127.0.0.1" "$@"; }
code() { c -o /dev/null -w '%{http_code}' "$@"; }
location() { c -o /dev/null -w '%{redirect_url}' "$1"; }
wp() { docker exec wordpress wp --allow-root --path=/var/www/html "$@" 2>/dev/null; }

section "The front page at /, the landing at /dream/"
c "$BASE/dream/" > "$TMP/landing.html"
if grep -q '/_dream/' "$TMP/landing.html" && grep -q 'A dream within' "$TMP/landing.html" && ! grep -q 'wp-content' "$TMP/landing.html"; then
    pass "S01 /dream/ is the prerendered landing (headline in the HTML, no WordPress)"
else
    fail "S01 /dream/ is not the landing" "$(head -c 200 "$TMP/landing.html")"
fi
JS=$(grep -oE '/_dream/[A-Za-z0-9_.-]+\.js' "$TMP/landing.html" | head -1)
CSS=$(grep -oE '/_dream/[A-Za-z0-9_.-]+\.css' "$TMP/landing.html" | head -1)
CC=$(c -o /dev/null -D - "$BASE$JS" | tr -d '\r' | sed -n 's/^cache-control: *//Ip' | head -1)
if [ -n "$JS" ] && [ "$(code "$BASE$JS")" = 200 ] && printf '%s' "$CC" | grep -q immutable; then
    pass "S02 hashed bundle served under /_dream/ with an immutable cache ($JS)"
else
    fail "S02 landing bundle" "js=$JS cache-control=$CC"
fi
c "$BASE$CSS" > "$TMP/landing.css"
EXTERNAL=$(grep -oE '(src|href)="https?://[^"]+"' "$TMP/landing.html"; grep -oE 'url\((https?:)?//[^)]+\)' "$TMP/landing.css")
if [ -z "$EXTERNAL" ]; then
    pass "S03 the landing loads nothing from another host (fonts and scripts self-hosted)"
else
    fail "S03 third-party request in the landing" "$(printf '%s' "$EXTERNAL" | head -3)"
fi
c "$BASE/" > "$TMP/front.html"
BAD=""
grep -q 'wp-\(content\|includes\)' "$TMP/front.html" || BAD="$BAD not-wordpress"
grep -q '<body[^>]*class="[^"]*\bhome\b' "$TMP/front.html" || BAD="$BAD not-the-front-page"
grep -q 'class="front-content prose' "$TMP/front.html" || BAD="$BAD page-content-not-rendered"
for href in /dream/ /deeper/ /blog/ /wiki/; do
    grep -q "href=\"[^\"]*$href\"" "$TMP/front.html" || BAD="$BAD no-link:$href"
done
case "$(location "$BASE/dream")" in */dream/) ;; *) BAD="$BAD /dream-not-301" ;; esac
c "$BASE/?s=nginx" | grep -q 'wp-\(content\|includes\)' || BAD="$BAD search-off-wordpress"
if [ -z "$BAD" ]; then
    pass "S04 / is WordPress's front page (its page content rendered) and links the landing, Deeper, the blog and the wiki"
else
    fail "S04 front page:$BAD"
fi

section "The blog"
if [ "$(code "$BASE/blog/")" = 200 ] && c "$BASE/blog/" | grep -q 'post-card'; then
    pass "S05 /blog/ lists the posts"
else
    fail "S05 /blog/ does not list posts"
fi
L=$(location "$BASE/journal/")
L2=$(location "$BASE/docs/")
case "$L $L2" in
    */blog/\ */wiki/) pass "S06 /journal/ answers 301 → /blog/, weDocs' /docs/ → /wiki/" ;;
    *) fail "S06 /journal/ or /docs/ does not redirect" "journal → $L, docs → $L2" ;;
esac

section "The wiki"
AREAS=$(c "$BASE/wiki/" | grep -c 'class="area-card')
if [ "$AREAS" -ge 5 ]; then
    pass "S07 /wiki/ shows its $AREAS areas"
else
    fail "S07 /wiki/ shows $AREAS areas (want 5)"
fi
# Easy TOC draws a table only from three headings up: the deep page has to be
# one with three (lab-api, the first choice, has none and never could pass).
DEEP="$BASE/wiki/engineering/measured-results/benchmarks/"
c "$DEEP" > "$TMP/deep.html"
MISSING=""
for marker in wiki-tree ez-toc-container; do
    grep -q "$marker" "$TMP/deep.html" || MISSING="$MISSING $marker"
done
if [ -z "$MISSING" ]; then
    pass "S08 a page three levels deep renders with its tree and table of contents"
else
    fail "S08 ${DEEP#"$BASE"} lacks:$MISSING" "code=$(code "$DEEP")"
fi
WANT=$(grep -c '"slug"' srcs/requirements/wordpress/site/content/wiki/tree.json)
HAVE=$(wp post list --post_type=docs --post_status=publish --format=count)
if [ "$HAVE" = "$WANT" ]; then
    pass "S09 every page of tools/wiki is published ($HAVE)"
else
    fail "S09 wiki pages: $HAVE published, tree.json has $WANT"
fi
L=$(location "$BASE/defense-qa/")
case "$L" in
    */wiki/defense/defense-qa/) pass "S10 a page the wiki replaced answers 301 → its wiki page" ;;
    *) fail "S10 /defense-qa/ does not redirect into the wiki" "redirect_url=$L" ;;
esac
if c "$BASE/?s=MariaDB&post_type=docs" | grep -q 'kind-wiki'; then
    pass "S11 search finds wiki pages"
else
    fail "S11 searching the wiki for MariaDB found nothing"
fi

section "Inside the containers"
BAD=""
for line in $(grep -vE '^[[:space:]]*(#|$)' srcs/requirements/wordpress/site/plugins.txt | tr ' ' '@'); do
    slug=${line%@*}; ver=${line#*@}
    got=$(wp plugin get "$slug" --field=version)
    st=$(wp plugin get "$slug" --field=status)
    [ "$got" = "$ver" ] && [ "$st" = active ] || BAD="$BAD $slug($got,$st≠$ver)"
done
[ "$(wp plugin get inception-kit --field=status)" = active ] || BAD="$BAD inception-kit(inactive)"
if [ -z "$BAD" ]; then
    pass "S12 inception-kit and every plugin in plugins.txt are active, at their pins"
else
    fail "S12 plugins inactive or off their pin:$BAD"
fi
if docker exec staticsite sh -c 'command -v node || command -v npm || command -v php' >/dev/null 2>&1; then
    fail "S13 the landing image ships node, npm or php"
else
    pass "S13 the landing image ships nginx only (no node, no npm, no php)"
fi
L=$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 5 --resolve "$DOMAIN:8090:127.0.0.1" "http://$DOMAIN:8090/blog/")
case "$L" in
    "https://$DOMAIN/blog/") pass "S14 on the bonus port, a link to the blog is sent to the HTTPS site" ;;
    *) fail "S14 :8090/blog/ does not redirect to https://$DOMAIN/blog/" "redirect_url=$L" ;;
esac

section "Diagrams and the guide series"
c "$BASE/wiki/architecture/" > "$TMP/arch.html"
MJS=$(c -o /dev/null -w '%{content_type}' "$BASE/wp-content/themes/inception-terminal/assets/vendor/mermaid/mermaid.esm.min.mjs")
if grep -q 'class="mermaid"' "$TMP/arch.html" && case "$MJS" in *javascript*) true ;; *) false ;; esac; then
    pass "S15 the wiki's diagrams are Mermaid, served from the theme as JavaScript"
else
    fail "S15 no Mermaid diagram on /wiki/architecture/, or the module's type is wrong" "content-type=$MJS"
fi
MISSING=""
for slug in $(grep -o '"slug": "[^"]*"' srcs/requirements/wordpress/site/content/posts/series.json | cut -d'"' -f4); do
    [ "$(wp post list --post_type=post --post_status=publish --name="$slug" --format=count)" = 1 ] || MISSING="$MISSING $slug"
done
if [ -z "$MISSING" ]; then
    pass "S16 every post of content/posts/series.json is published"
else
    fail "S16 series posts missing:$MISSING"
fi

section "The maintainers' door"
c "$BASE/wp-login.php" > "$TMP/login.html"
if grep -q 'inception-login-note' "$TMP/login.html" && ! grep -q 'action=lostpassword' "$TMP/login.html"; then
    pass "S17 /wp-login.php wears the site's design and offers no mail reset"
else
    fail "S17 the sign-in page is unbranded or still links a password reset"
fi
EMAIL=$(sed -n 's/^WP_ADMIN_EMAIL=//p' srcs/.env)
ADMIN_PW=$(sed -n 1p secrets/credentials.txt 2>/dev/null)
# The arguments travel through docker exec, never a shell: no quoting to break.
if wp user check-password "$EMAIL" "$ADMIN_PW" > /dev/null; then
    pass "S18 the administrator signs in with WP_ADMIN_EMAIL and line 1 of secrets/credentials.txt"
else
    fail "S18 WP_ADMIN_EMAIL plus the admin secret does not authenticate" "email=$EMAIL"
fi
BAD=""
[ "$(code "$BASE/xmlrpc.php")" = 403 ] || BAD="$BAD xmlrpc.php≠403"
[ "$(code "$BASE/wp-json/wp/v2/users")" = 404 ] || BAD="$BAD users-route-open"
[ "$(code "$BASE/?author=1")" = 404 ] || BAD="$BAD ?author=1≠404"
c -D "$TMP/headers" -o /dev/null "$BASE/blog/"
grep -qi '^x-content-type-options: nosniff' "$TMP/headers" || BAD="$BAD no-nosniff"
grep -qi "^content-security-policy: frame-ancestors 'self'" "$TMP/headers" || BAD="$BAD no-frame-ancestors"
grep -qi '^x-powered-by' "$TMP/headers" && BAD="$BAD x-powered-by"
if [ -z "$BAD" ]; then
    pass "S19 XML-RPC refused, accounts not listable, security headers on every page"
else
    fail "S19 hardening missing:$BAD"
fi
# The theme's files are immutable for 30 days, so only a new URL reaches a
# returning visitor: ?ver= must change with the content. Core's emoji loader
# would fetch images from s.w.org, the one third-party host WordPress names.
c "$BASE/blog/" > "$TMP/blog.html"
THEME_CSS=$(grep -oE '/wp-content/themes/inception-terminal/assets/theme\.css\?ver=[^"'"'"' ]+' "$TMP/blog.html" | head -1)
c -o /dev/null -D "$TMP/asset-headers" "$BASE$THEME_CSS"
BAD=""
grep -q 's\.w\.org' "$TMP/blog.html" && BAD="$BAD s.w.org"
printf '%s' "$THEME_CSS" | grep -qE 'ver=[0-9a-f]{12}$' || BAD="$BAD ver-not-a-hash:${THEME_CSS:-none}"
[ "$(grep -ci '^cache-control:' "$TMP/asset-headers")" = 1 ] || BAD="$BAD cache-control-count"
grep -qi '^cache-control:.*immutable' "$TMP/asset-headers" || BAD="$BAD not-immutable"
grep -qi '^x-content-type-options: nosniff' "$TMP/asset-headers" || BAD="$BAD asset-no-nosniff"
if [ -z "$BAD" ]; then
    pass "S21 WordPress loads nothing from another host; theme assets versioned by content"
else
    fail "S21 WordPress assets:$BAD"
fi
section "Deeper at /deeper/"
# The second staticsite app. Caveat: the third-party scan reads the HTML, the
# CSS and every chunk the page names for the CDN hosts a bundler or a font
# kit would add; a URL built at run time from pieces would slip past it.
c "$BASE/deeper/" > "$TMP/deeper.html"
DJS=$(grep -oE '/deeper/_world/[A-Za-z0-9_.-]+\.js' "$TMP/deeper.html" | head -1)
DCSS=$(grep -oE '/deeper/_world/[A-Za-z0-9_.-]+\.css' "$TMP/deeper.html" | head -1)
DCC=$(c -o /dev/null -D - "$BASE$DJS" | tr -d '\r' | sed -n 's/^cache-control: *//Ip' | head -1)
BAD=""
[ "$(location "$BASE/deeper")" = "$BASE/deeper/" ] || BAD="$BAD /deeper-not-301"
grep -q 'Go deeper' "$TMP/deeper.html" || BAD="$BAD headline-not-prerendered"
grep -q 'wp-content' "$TMP/deeper.html" && BAD="$BAD wordpress-markup"
{ [ -n "$DJS" ] && [ "$(code "$BASE$DJS")" = 200 ]; } || BAD="$BAD bundle:${DJS:-none}"
printf '%s' "$DCC" | grep -q immutable || BAD="$BAD not-immutable"
c "$BASE$DCSS" > "$TMP/deeper.css"
c "$BASE$DJS" > "$TMP/deeper.js"
for chunk in $(grep -oE '_world/[A-Za-z0-9_.-]+\.js' "$TMP/deeper.js" | sort -u); do
    c "$BASE/deeper/$chunk" >> "$TMP/deeper.js"
done
grep -qE '(src|href)="https?://' "$TMP/deeper.html" && BAD="$BAD html-external"
# the link card: absolute (nginx adds the host) and served
OG=$(grep -oE 'property="og:image" content="[^"]+"' "$TMP/deeper.html" | sed 's/.*content="//; s/"$//')
case "$OG" in
    "https://$DOMAIN/deeper/_world/"*) [ "$(code "$BASE${OG#https://$DOMAIN}")" = 200 ] || BAD="$BAD og-image-missing" ;;
    *) BAD="$BAD og-image:${OG:-none}" ;;
esac
grep -qE 'url\((https?:)?//' "$TMP/deeper.css" && BAD="$BAD css-external"
grep -qE '//(fonts\.(googleapis|gstatic)|cdn\.|unpkg\.com|cdn\.jsdelivr|[a-z0-9]+\.cloudfront\.net)' "$TMP/deeper.js" && BAD="$BAD js-cdn"
if [ -z "$BAD" ]; then
    pass "S22 /deeper/ is prerendered, its bundles immutable, its link card absolute, nothing from another host"
else
    fail "S22 Deeper:$BAD"
fi

# A post on a wide screen carries the rail kit.js fills; titles are in
# sentence case; the wiki's stats write units as the landing does (~13 s).
SLUG=$(grep -o '"slug": "[^"]*"' srcs/requirements/wordpress/site/content/posts/series.json | head -1 | cut -d'"' -f4)
c "$BASE/$SLUG/" > "$TMP/post.html"
BAD=""
grep -q 'class="prose ik-doc-content"' "$TMP/post.html" || BAD="$BAD no-doc-content"
grep -q 'class="ik-toc entry-rail"' "$TMP/post.html" || BAD="$BAD no-rail"
# Caveat: "sentence case" here means the first letter is a capital, except
# for a name its own project writes in lower case ("nginx, the only door");
# a title opening on another such name (systemd, say) fails until it is
# added to the list below.
LOWER=$(wp post list --post_type=post --post_status=publish --field=post_title | grep '^[a-z]' | grep -vE '^(nginx|php-fpm|hellish|npm)\b' | head -2 | tr '\n' ';')
[ -z "$LOWER" ] || BAD="$BAD lower-case-title:$LOWER"
STATS=$(wp post list --post_type=docs --post_status=publish --name=benchmarks --field=url | head -1)
c "${STATS:-$BASE/wiki/}" > "$TMP/stats.html"
grep -q 'ik-stat-value' "$TMP/stats.html" || BAD="$BAD no-stats-on:${STATS:-benchmarks-missing}"
grep -qE 'ik-stat-value">[^<]*[0-9](s|MB)<' "$TMP/stats.html" && BAD="$BAD unit-without-space"
if [ -z "$BAD" ]; then
    pass "S23 posts carry the on-this-page rail, titles in sentence case, stats spaced (~13 s)"
else
    fail "S23 post layout or wording:$BAD"
fi

# Last on purpose: 8 wrong passwords in a row spend the sign-in burst, and the
# limit is per client address, so for ~30 s after this a browser on the same
# host (behind the same NAT) may meet a 429 too.
GOT429=0
for _ in 1 2 3 4 5 6 7 8; do
    [ "$(code -d 'log=nobody&pwd=wrong' "$BASE/wp-login.php")" = 429 ] && GOT429=1
done
if [ "$GOT429" = 1 ]; then
    pass "S20 a burst of sign-in attempts is answered 429"
else
    fail "S20 8 sign-in POSTs in a row were never rate-limited"
fi

printf "\n  ${GRN}%d passed${RST}  ${RED}%d failed${RST}\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
