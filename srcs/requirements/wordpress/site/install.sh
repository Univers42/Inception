#!/bin/hellish
# shellcheck shell=sh
set -eu

SRC=/usr/src/inception-site
WEBROOT=/var/www/html

[ -f "$WEBROOT/wp-config.php" ] || {
    echo "[site] WordPress not installed yet — skipping"
    exit 0
}

for pair in "theme/inception-terminal:themes" "plugin/inception-kit:plugins"; do
    src_rel=${pair%%:*}
    dest_kind=${pair##*:}
    name=$(basename "$src_rel")
    dest="$WEBROOT/wp-content/$dest_kind/$name"
    rm -rf "$dest"
    mkdir -p "$WEBROOT/wp-content/$dest_kind"
    cp -a "$SRC/$src_rel" "$dest"
    chown -R nobody:nobody "$dest"
done

# Third-party plugins (site/plugins.txt), unpacked into the image at build
# time. The image is the source of truth here exactly as for the theme above:
# each one is replaced on every boot, then activated if it is not, so the
# container never downloads code while it starts.
PLUGINS=/usr/src/inception-plugins
slugs=$(grep -vE '^[[:space:]]*(#|$)' "$SRC/plugins.txt" | cut -d' ' -f1)
for slug in $slugs; do
    if [ ! -d "$PLUGINS/$slug" ]; then
        echo "[site] plugin $slug is listed but missing from the image" >&2
        continue
    fi
    dest="$WEBROOT/wp-content/plugins/$slug"
    rm -rf "$dest"
    cp -a "$PLUGINS/$slug" "$dest"
    chown -R nobody:nobody "$dest"
done
# The kit by name too: WP-CLI exits 1 on a plugin it cannot find, so a kit
# that lost its header stops here rather than leaving the wiki unrouted.
# shellcheck disable=SC2086 # one word per slug
wp --allow-root --path="$WEBROOT" plugin activate inception-kit $slugs --quiet

wp --allow-root --path="$WEBROOT" eval-file "$SRC/seed.php"
wp --allow-root --path="$WEBROOT" eval-file "$SRC/wiki.php"
wp --allow-root --path="$WEBROOT" eval-file "$SRC/posts.php"
