#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================
# User-editable defaults (can be overridden here)
# ==============================
VM_NAME="rhl"
VM_OS_TYPE="${VM_OS_TYPE:-RedHat_64}"      # VirtualBox OS Type for RHEL-like distros
VM_CPUS="${VM_CPUS:-2}"
VM_MEMORY="${VM_MEMORY:-4096}"             # MB
VM_DISK_SIZE="${VM_DISK_SIZE:-32768}"      # MB
VM_NETWORK_TYPE="${VM_NETWORK_TYPE:-nat}"  # nat | bridged
VM_BASE_PATH="${VM_BASE_PATH:-/home/dlesieur/VMS}"
ISO_PATH="${ISO_PATH:-/home/dlesieur/Downloads/rhel-10.0-x86_64-dvd.iso}" # Fixed: single valid path, absolute
HOST_SSH_PORT="${HOST_SSH_PORT:-4242}"
GUEST_SSH_PORT="${GUEST_SSH_PORT:-22}"
HOST_HTTP_PORT="${HOST_HTTP_PORT:-8080}"
GUEST_HTTP_PORT="${GUEST_HTTP_PORT:-80}"
VM_HOSTNAME="${VM_HOSTNAME:-dlesieur}"
KS_FILE_PATH="${KS_FILE_PATH:-$(pwd)/ks.cfg}"  # Changed from preset-ks.cfg to ks.cfg
AUTO_START_HTTP="${AUTO_START_HTTP:-false}"     # true|false
BRIDGE_ADAPTER="${BRIDGE_ADAPTER:-}"           # Required only if VM_NETWORK_TYPE=bridged

# Derived paths
VM_HOME_DIR="${VM_BASE_PATH}/${VM_NAME}"
VM_DISK_PATH="${VM_DISK_PATH:-${VM_HOME_DIR}/${VM_NAME}.vdi}"

print_header()
{
    echo "================"
    echo "      $1"
    echo "================"
}

die() { echo "Error: $*" >&2; exit 1; }
log() { echo "[*] $*"; }

cleanup_vm() {
    local vm_name="$1"
    log "Cleaning up VM state for: $vm_name"
    
    # Try to power off if running
    VBoxManage controlvm "$vm_name" poweroff 2>/dev/null || true
    sleep 2
    
    # Remove saved state if any
    VBoxManage discardstate "$vm_name" 2>/dev/null || true
    
    # Unregister and delete
    VBoxManage unregistervm "$vm_name" --delete 2>/dev/null || true
    
    # Clean up any orphaned VDI files
    if [ -d "$VM_BASE_PATH/$vm_name" ]; then
        rm -rf "$VM_BASE_PATH/$vm_name"
    fi
    
    # Clean up boot ISOs
    rm -f "$VM_BASE_PATH/kickstart-boot.iso"
}

# Create an auto-boot ISO with embedded Kickstart boot params
create_autoboot_iso() {
    log "Creating automated boot ISO with Kickstart..."
    local auto_iso="$VM_BASE_PATH/rhel-auto-ks.iso"
    local ks_url="http://10.0.2.2:$HOST_HTTP_PORT/$(basename "$KS_FILE_PATH")"

    # Reuse if newer than ks.cfg
    if [ -f "$auto_iso" ] && [ "$auto_iso" -nt "$KS_FILE_PATH" ]; then
        log "Using existing auto-boot ISO: $auto_iso"
        echo "$auto_iso"
        return 0
    fi

    if bash "$SCRIPT_DIR/create_boot_iso.sh" "$ISO_PATH" "$(basename "$KS_FILE_PATH")" "$auto_iso" "$ks_url"; then
        log "Auto-boot ISO created: $auto_iso"
        echo "$auto_iso"
    else
        log "Warning: Auto-boot ISO build failed, falling back to original ISO"
        echo "$ISO_PATH"
    fi
}

trap 'echo "An unexpected error occurred. Aborting." >&2' ERR

# ==============================
# Preconditions
# ==============================
command -v VBoxManage >/dev/null 2>&1 || die "VirtualBox (VBoxManage) not found in PATH."
[ -f "$ISO_PATH" ] || die "ISO not found at: $ISO_PATH"

mkdir -p "$VM_HOME_DIR"

# If VM exists, prompt for deletion
if VBoxManage showvminfo "$VM_NAME" &>/dev/null; then
    read -r -p "VM '$VM_NAME' already exists. Delete and recreate (y/n): " confirm
    if [[ $confirm =~ ^[yY]$ ]]; then
        log "Removing existing VM..."
        cleanup_vm "$VM_NAME"
        sleep 2  # Give VirtualBox time to release resources
    else
        echo "Exiting without changes."
        exit 0
    fi
fi

print_header "Creating VM"
VBoxManage createvm --name "$VM_NAME" --ostype "$VM_OS_TYPE" --register --basefolder "$VM_BASE_PATH" || die "Failed to create VM"

log "Configuring VM hardware..."
VBoxManage modifyvm "$VM_NAME" \
    --memory "$VM_MEMORY" \
    --cpus "$VM_CPUS" \
    --vram 16 \
    --ioapic on \
    --acpi on \
    --rtcuseutc on \
    --chipset ich9 \
    --graphicscontroller vboxvga \
    --uart1 0x3F8 4 \
    --uartmode1 file /tmp/vbox-${VM_NAME}-serial.log

# Networking
if [[ "$VM_NETWORK_TYPE" == "bridged" ]]; then
    [[ -n "$BRIDGE_ADAPTER" ]] || die "BRIDGE_ADAPTER must be set when VM_NETWORK_TYPE=bridged"
    VBoxManage modifyvm "$VM_NAME" --nic1 bridged --bridgeadapter1 "$BRIDGE_ADAPTER"
else
    VBoxManage modifyvm "$VM_NAME" --nic1 nat
fi

# ==============================
# Storage
# ==============================
print_header "Setting up storage"
# Create disk
VBoxManage createmedium disk --filename "$VM_DISK_PATH" --size "$VM_DISK_SIZE" --format VDI
# SATA for disk
VBoxManage storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAhci
VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$VM_DISK_PATH"
# IDE for DVD - attach auto-boot ISO (fallback to original on failure)
VBoxManage storagectl "$VM_NAME" --name "IDE Controller" --add ide --controller PIIX4
AUTO_ISO="$(create_autoboot_iso 2>/dev/null || echo "$ISO_PATH")"
if [ ! -f "$AUTO_ISO" ]; then
    log "Auto-boot ISO not found or failed, falling back to original ISO."
    AUTO_ISO="$ISO_PATH"
    echo "WARNING: You will need to manually edit GRUB and add the kernel parameters for Kickstart."
fi
log "Using ISO: $AUTO_ISO"
VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "$AUTO_ISO"

# ==============================
# Optional performance/UX tweaks
# ==============================
log "Optimizing VM (disable audio/USB/GUI, clipboard/drag&drop disabled)..."
VBoxManage modifyvm "$VM_NAME" --audio-driver none --usb off --clipboard disabled --draganddrop disabled
# Enable VRDE for remote console access (instead of --vrde off)
VBoxManage modifyvm "$VM_NAME" --vrde on --vrdeport 3389 --vrdeaddress 127.0.0.1

# ==============================
# NAT port forwarding (only if NAT)
# ==============================
if [[ "$VM_NETWORK_TYPE" == "nat" ]]; then
    print_header "Configuring NAT port forwarding"
    # Delete if present (ignore errors)
    VBoxManage modifyvm "$VM_NAME" --natpf1 delete "guestssh" 2>/dev/null || true
    VBoxManage modifyvm "$VM_NAME" --natpf1 delete "guesthttp" 2>/dev/null || true

    log "Setting up SSH host:$HOST_SSH_PORT -> guest:$GUEST_SSH_PORT"
    VBoxManage modifyvm "$VM_NAME" --natpf1 "guestssh,tcp,,$HOST_SSH_PORT,,$GUEST_SSH_PORT"
    log "Setting up HTTP host:$HOST_HTTP_PORT -> guest:$GUEST_HTTP_PORT"
    VBoxManage modifyvm "$VM_NAME" --natpf1 "guesthttp,tcp,,$HOST_HTTP_PORT,,$GUEST_HTTP_PORT"
fi

# ==============================
# Boot order
# ==============================
VBoxManage modifyvm "$VM_NAME" --boot1 dvd --boot2 disk --boot3 none --boot4 none

# ==============================
# Final instructions
# ==============================
echo "VM created successfully at: $VM_HOME_DIR"
echo ""
echo "AUTOMATED INSTALLATION:"
echo "  For the first boot, start the VM with GUI to see the GRUB menu:"
echo "    VBoxManage startvm \"$VM_NAME\" --type gui"
echo "  Use VNC if you prefer, but GUI is more reliable for server ISOs."
echo ""
echo "  At the GRUB menu, press 'e' and add to the linux/linuxefi line:"
echo "    inst.ks=http://10.0.2.2:$HOST_HTTP_PORT/$(basename "$KS_FILE_PATH") inst.text console=ttyS0,115200n8"
echo "  Press Ctrl+X to boot."
echo ""
echo "  After installation, you can use headless mode:"
echo "    VBoxManage startvm \"$VM_NAME\" --type headless"
echo ""
if [[ "$VM_NETWORK_TYPE" == "nat" ]]; then
    echo "After installation:"
    echo "  SSH: ssh -p $HOST_SSH_PORT dlesieur@localhost"
    echo "  Password: tempuser123 (change after first login)"
fi