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

wp --allow-root --path="$WEBROOT" eval-file "$SRC/seed.php"
