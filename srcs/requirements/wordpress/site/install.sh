#!/bin/sh
# ═════════════════════════════════════════════════════════════════════
#  Inception site provisioning — theme, plugin and documentation content.
#
#  Called by the wordpress entrypoint on every boot (non-fatal there).
#  Files are re-synced from the image so container recreation deploys
#  updates; all WordPress-side work happens in a SINGLE PHP process
#  (seed.php via `wp eval-file`) to keep first-boot time low. Fully
#  idempotent — every object is guarded by an existence check and the
#  content phase short-circuits on a marker option.
# ═════════════════════════════════════════════════════════════════════
set -eu

SRC=/usr/src/inception-site
WEBROOT=/var/www/html

[ -f "$WEBROOT/wp-config.php" ] || {
    echo "[site] WordPress not installed yet — skipping"
    exit 0
}

# ── 1. Deploy theme + plugin (repo/image is the source of truth) ─────
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

# ── 2. Activation, permalinks and one-time content — one PHP boot ────
wp --allow-root --path="$WEBROOT" eval-file "$SRC/seed.php"
