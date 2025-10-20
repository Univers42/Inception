#!/usr/bin/env bash
set -euo pipefail

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
ISO_PATH="${ISO_PATH:-/Downloads/rhel-9.4-x86_64-dvd.iso}" # Adjust to your ISO
HOST_SSH_PORT="${HOST_SSH_PORT:-4242}"
GUEST_SSH_PORT="${GUEST_SSH_PORT:-22}"
HOST_HTTP_PORT="${HOST_HTTP_PORT:-8080}"
GUEST_HTTP_PORT="${GUEST_HTTP_PORT:-80}"
VM_HOSTNAME="${VM_HOSTNAME:-dlesieur}"
KS_FILE_PATH="${KS_FILE_PATH:-$(pwd)/ks.cfg}"  # RHEL Kickstart, not Debian preseed
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
        VBoxManage unregistervm "$VM_NAME" --delete
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
    --vram 32 \
    --ioapic on \
    --acpi on \
    --rtcuseutc on \
    --chipset ich9 \
    --graphicscontroller vmsvga

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
# IDE for DVD
VBoxManage storagectl "$VM_NAME" --name "IDE Controller" --add ide --controller PIIX4
VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "$ISO_PATH"

# ==============================
# Optional performance/UX tweaks
# ==============================
log "Optimizing VM (disable audio/USB, clipboard/drag&drop disabled)..."
VBoxManage modifyvm "$VM_NAME" --audio none --usb off --clipboard disabled --draganddrop disabled

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
# RHEL Kickstart guidance
# ==============================
print_header "RHEL Kickstart (Automated Install)"
# Detect a likely host IP (to serve ks.cfg)
HOST_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
HOST_IP="${HOST_IP:-127.0.0.1}"

echo "To automate the RHEL installation with Kickstart:"
echo "1) Place your Kickstart file at: $KS_FILE_PATH"
echo "   Minimal example references: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html-single/performing_an_advanced_rhel_9_installation/index#kickstart-reference"
echo "		> All kickstart scripts and the log files of their execution are storied in the /tmp directory to assist installation failures"
echo "2) Serve it over HTTP (from its directory):"
echo "   cd \"$(dirname "$KS_FILE_PATH")\" && python3 -m http.server $HOST_HTTP_PORT"
echo ""
echo "3) At the installer boot menu (from the ISO), press 'e' (or Tab) to edit kernel params and append:"
echo "   inst.ks=http://$HOST_IP:$HOST_HTTP_PORT/$(basename "$KS_FILE_PATH") inst.text"
echo "   Optional console for headless: console=ttyS0,115200n8"
echo ""
echo "4) Set the VM hostname during install or via Kickstart. Current setting: $VM_HOSTNAME"
echo ""

# Optional: start HTTP server automatically
if [[ "$AUTO_START_HTTP" == "true" ]]; then
    log "Attempting to auto-start HTTP server on $HOST_IP:$HOST_HTTP_PORT serving $(dirname "$KS_FILE_PATH")"
    (cd "$(dirname "$KS_FILE_PATH")" && python3 -m http.server "$HOST_HTTP_PORT" >/dev/null 2>&1 &)
    echo "HTTP server started in background."
fi

# ==============================
# Final instructions
# ==============================
echo "VM created successfully at: $VM_HOME_DIR"
echo "Start the VM with: VBoxManage startvm \"$VM_NAME\" --type gui"
echo "Headless:          VBoxManage startvm \"$VM_NAME\" --type headless"
echo ""
if [[ "$VM_NETWORK_TYPE" == "nat" ]]; then
    echo "SSH (after install): ssh -p $HOST_SSH_PORT user@$HOST_IP"
    echo "HTTP (guest:$GUEST_HTTP_PORT): http://$HOST_IP:$HOST_HTTP_PORT/"
fi