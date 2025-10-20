#!/usr/bin/env bash
set -euo pipefail

# Args:
# 1: Path to original RHEL ISO
# 2: Kickstart filename in current dir (e.g., ks.cfg)
# 3: Output ISO path
# 4: Kickstart URL to inject into kernel cmdline
RHEL_ISO="${1:-}"
KS_FILE_NAME="${2:-ks.cfg}"
OUTPUT_ISO="${3:-rhel-auto-ks.iso}"
KS_URL="${4:-http://10.0.2.2:8080/ks.cfg}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KS_FILE_PATH="$SCRIPT_DIR/$KS_FILE_NAME"

log() { echo "[*] $*"; }
die() { echo "Error: $*" >&2; exit 1; }

[ -n "${RHEL_ISO}" ] || die "Usage: create_boot_iso.sh <rhel.iso> <ks.cfg> <output.iso> <ks_url>"
[ -f "$RHEL_ISO" ] || die "RHEL ISO not found: $RHEL_ISO"
[ -f "$KS_FILE_PATH" ] || die "Kickstart file not found: $KS_FILE_PATH"

# Dependencies
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found. Install it."; }
need xorriso
need isoinfo
if ! command -v implantisomd5 >/dev/null 2>&1; then
    log "implantisomd5 not found, checksum step will be skipped"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log "Preparing extraction directories..."
# Pre-create all top-level directories from ISO
for dir in $(xorriso -indev "$RHEL_ISO" -ls_l / | awk '/^d/ {print $9}'); do
    mkdir -p "$WORK_DIR/$dir"
done

log "Extracting ISO (no root required)..."
xorriso -osirrox on -indev "$RHEL_ISO" -extract / "$WORK_DIR" || die "ISO extraction failed"

# Copy ks.cfg to ISO root as fallback
cp "$KS_FILE_PATH" "$WORK_DIR/$KS_FILE_NAME"

# Locate boot configs
GRUB_CFG="$(find "$WORK_DIR" -type f -name 'grub.cfg' | head -n1 || true)"
ISOLINUX_CFG="$(find "$WORK_DIR" -type f -name 'isolinux.cfg' -o -name 'isolinux/isolinux.cfg' | head -n1 || true)"

if [ -z "$GRUB_CFG" ] && [ -z "$ISOLINUX_CFG" ]; then
    die "Could not find grub.cfg or isolinux.cfg in ISO"
fi

log "Patching bootloader config to auto-use Kickstart..."
APPEND_ARGS="inst.ks=${KS_URL} inst.text console=ttyS0,115200n8"

# Patch GRUB (EFI) first if present
if [ -n "$GRUB_CFG" ]; then
    cp "$GRUB_CFG" "${GRUB_CFG}.orig"
    # Append only to the first 'linux' or 'linuxefi' occurrence
    sed -i '0,/^[[:space:]]*linux\(efi\)\?[[:space:]]/ s|\(^[[:space:]]*linux\(efi\)\?[[:space:]][^$]*\)$|\1 '"$APPEND_ARGS"'|;' "$GRUB_CFG"
    # Reduce timeout
    sed -i 's/^set timeout=.*/set timeout=5/' "$GRUB_CFG" || true
fi

# Patch isolinux (BIOS) as well if present
if [ -n "$ISOLINUX_CFG" ]; then
    cp "$ISOLINUX_CFG" "${ISOLINUX_CFG}.orig"
    sed -i '0,/^[[:space:]]*append[[:space:]]/ s|\(^[[:space:]]*append[[:space:]][^$]*\)$|\1 '"$APPEND_ARGS"'|;' "$ISOLINUX_CFG"
    sed -i 's/^\(timeout\).*/\1 50/' "$ISOLINUX_CFG" || true
fi

# Determine volume label
VOL_ID="$(isoinfo -d -i "$RHEL_ISO" 2>/dev/null | awk -F': ' '/Volume id:/ {print $2}' | xargs || true)"
VOL_ID="${VOL_ID:-RHEL-AUTO}"

log "Rebuilding hybrid (BIOS+UEFI) ISO..."
# Build options assume typical RHEL tree with isolinux and efiboot image present
# If paths differ, xorriso will warn; we keep output concise.
xorriso -as mkisofs \
  -V "$VOL_ID" \
  -r -J -joliet-long \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e images/efiboot.img \
  -no-emul-boot \
  -isohybrid-mbr "$WORK_DIR"/isolinux/isohdpfx.bin 2>/dev/null || true

# Some RHEL ISOs may not contain isohdpfx.bin; rebuild without MBR if missing
if [ ! -f "$OUTPUT_ISO" ]; then
  xorriso -as mkisofs \
    -V "$VOL_ID" \
    -r -J -joliet-long \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e images/efiboot.img \
    -no-emul-boot \
    -o "$OUTPUT_ISO" \
    "$WORK_DIR" >/dev/null
else
  # If previous command printed to stdout only, ensure we actually write the ISO
  xorriso -as mkisofs \
    -V "$VOL_ID" \
    -r -J -joliet-long \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e images/efiboot.img \
    -no-emul-boot \
    -o "$OUTPUT_ISO" \
    "$WORK_DIR" >/dev/null
fi

# Add ISO checksum if tool available
if command -v implantisomd5 >/dev/null 2>&1; then
    log "Adding ISO checksum..."
    implantisomd5 "$OUTPUT_ISO" >/dev/null || true
fi

log "Boot ISO created: $OUTPUT_ISO"
log "Kickstart URL: $KS_URL"
log "Kickstart fallback embedded at: /$KS_FILE_NAME"
