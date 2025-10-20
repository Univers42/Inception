#!/usr/bin/env bash
set -euo pipefail

RHEL_ISO="${1:-/home/dlesieur/Downloads/rhel-10.0-x86_64-dvd.iso}"
KS_FILE="${2:-ks.cfg}"
OUTPUT_ISO="${3:-rhel-auto-ks.iso}"
KS_URL="${4:-http://10.0.2.2:8080/ks.cfg}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[*] $*"; }
die() { echo "Error: $*" >&2; exit 1; }

# Check dependencies
for cmd in xorriso implantisomd5; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "Installing $cmd..."
        sudo apt-get update && sudo apt-get install -y xorriso isomd5sum
    fi
done

[ -f "$RHEL_ISO" ] || die "RHEL ISO not found: $RHEL_ISO"
[ -f "$SCRIPT_DIR/$KS_FILE" ] || die "Kickstart file not found: $SCRIPT_DIR/$KS_FILE"

log "Creating automated installation ISO from RHEL ISO..."

# Create working directories
WORK_DIR=$(mktemp -d)
ISO_MOUNT=$(mktemp -d)
trap "sudo umount $ISO_MOUNT 2>/dev/null || true; rm -rf $WORK_DIR $ISO_MOUNT" EXIT

# Mount the original ISO
log "Mounting original RHEL ISO..."
sudo mount -o loop "$RHEL_ISO" "$ISO_MOUNT"

# Copy ISO contents
log "Extracting ISO contents (this may take a few minutes)..."
rsync -a "$ISO_MOUNT/" "$WORK_DIR/"
sudo umount "$ISO_MOUNT"

# Make files writable
chmod -R u+w "$WORK_DIR"

# Find and modify GRUB config
GRUB_CFG=$(find "$WORK_DIR" -name "grub.cfg" | head -1)

if [ -z "$GRUB_CFG" ]; then
    die "Could not find grub.cfg in ISO"
fi

log "Modifying boot configuration: $GRUB_CFG"

# Backup original
cp "$GRUB_CFG" "${GRUB_CFG}.orig"

# Modify the first menuentry to append Kickstart and console params safely
# Find the first 'linux' or 'linuxefi' line and append our params
if [ -n "$GRUB_CFG" ]; then
    cp "$GRUB_CFG" "${GRUB_CFG}.orig"
    # Only append, do not replace the line
    sed -i '0,/^[[:space:]]*linux\(efi\)\?[[:space:]]/ s|\(^[[:space:]]*linux\(efi\)\?[[:space:]][^$]*\)$|\1 '" $KS_URL inst.text console=ttyS0,115200n8"'|;' "$GRUB_CFG"
    sed -i 's/^set timeout=.*/set timeout=5/' "$GRUB_CFG" || true
fi

# Embed kickstart file into ISO as fallback
cp "$SCRIPT_DIR/$KS_FILE" "$WORK_DIR/"

log "Rebuilding ISO..."
# Detect volume ID from original ISO
VOL_ID=$(isoinfo -d -i "$RHEL_ISO" 2>/dev/null | grep "Volume id:" | cut -d: -f2 | xargs || echo "RHEL-AUTO")

xorriso -as mkisofs \
    -V "${VOL_ID}" \
    -r -J \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e images/efiboot.img \
    -no-emul-boot \
    -o "$OUTPUT_ISO" \
    "$WORK_DIR" 2>&1 | grep -v "^xorriso" || true

# Implant MD5 checksum
log "Adding checksum..."
implantisomd5 "$OUTPUT_ISO" 2>/dev/null || true

log "✓ Automated installation ISO created: $OUTPUT_ISO"
log "  Kickstart URL: $KS_URL"
