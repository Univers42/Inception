#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${1:-rhl}"
HTTP_PORT="${2:-8080}"
KS_FILE="${3:-ks.cfg}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERIAL_LOG="/tmp/vbox-${VM_NAME}-serial.log"
HTTP_LOG="/tmp/vbox-http-server.log"

log() { echo "[*] $*"; }
die() { echo "Error: $*" >&2; exit 1; }

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    command -v VBoxManage >/dev/null 2>&1 || die "VirtualBox not installed"
    
    if ! command -v socat >/dev/null 2>&1; then
        log "Installing socat..."
        sudo apt-get update && sudo apt-get install -y socat
    fi
    
    log "✓ All dependencies OK"
}

# Clean up ports
cleanup_port() {
    local port=$1
    if lsof -ti :"$port" >/dev/null 2>&1; then
        log "Freeing port $port..."
        lsof -ti :"$port" | xargs -r kill -9 2>/dev/null || true
        sleep 1
    fi
}

check_dependencies

# Check if VM exists
VBoxManage showvminfo "$VM_NAME" &>/dev/null || die "VM '$VM_NAME' does not exist. Run ./setup_vm.sh first"

# Check VM state
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep "VMState=" | cut -d'"' -f2)

if [[ "$VM_STATE" == "running" ]]; then
    log "VM '$VM_NAME' is already running"
    read -p "Stop and restart the VM? (y/n): " restart
    if [[ $restart =~ ^[yY]$ ]]; then
        log "Stopping VM..."
        VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
        sleep 3
    else
        log "Connecting to existing VM session..."
    fi
elif [[ "$VM_STATE" != "poweroff" && "$VM_STATE" != "aborted" ]]; then
    log "VM is in state: $VM_STATE. Forcing poweroff..."
    VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
    sleep 3
fi

# Check if Kickstart file exists
[ -f "$SCRIPT_DIR/$KS_FILE" ] || die "Kickstart file not found: $SCRIPT_DIR/$KS_FILE"

# Clean up and start HTTP server
cleanup_port "$HTTP_PORT"

log "Starting HTTP server on port $HTTP_PORT..."
cd "$SCRIPT_DIR"
python3 -m http.server "$HTTP_PORT" > "$HTTP_LOG" 2>&1 &
HTTP_PID=$!
log "HTTP server started (PID: $HTTP_PID)"

# Ensure HOST_SSH_PORT is set (default to 4242 if not)
HOST_SSH_PORT="${HOST_SSH_PORT:-4242}"

# Cleanup function
cleanup() {
    log "Cleaning up..."
    kill "$HTTP_PID" 2>/dev/null || true
    if [ -n "${TAIL_PID:-}" ]; then
        kill "$TAIL_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Wait for HTTP server to start
sleep 2

# Remove old serial log
rm -f "$SERIAL_LOG"

# Start VM only if not already running
if [[ "$VM_STATE" != "running" ]]; then
    log "Starting VM '$VM_NAME' in VRDE mode for remote console access..."
    VBoxManage startvm "$VM_NAME" --type separate
    sleep 3
fi

# Wait for serial log
log "Waiting for serial console log..."
for i in {1..30}; do
    if [ -f "$SERIAL_LOG" ]; then
        log "Serial log ready"
        break
    fi
    sleep 1
done

log ""
log "=================================="
log "VM STARTED - Automated Installation"
log "=================================="
log "VM Name: $VM_NAME"
log "Kickstart HTTP URL: http://10.0.2.2:$HTTP_PORT/$KS_FILE"
log "Serial log file: $SERIAL_LOG"
log "HTTP server log: $HTTP_LOG"
log "Remote Console (VRDE): localhost:3389"
log "=================================="
log ""
log "IMPORTANT:"
log "  If the VNC window is black, start the VM with GUI for the first boot:"
log "    VBoxManage startvm \"$VM_NAME\" --type gui"
log "  This will show the GRUB menu even for server ISOs."
log "  After installation, you can use headless mode for server operation."
log ""
log "NEXT STEPS:"
log "1. Use VNC (vncviewer localhost:3389) ONLY to edit the GRUB boot menu:"
log "   - At the GRUB menu, press 'e' to edit."
log "   - Add to the end of the linux/linuxefi line:"
log "       inst.ks=http://10.0.2.2:$HTTP_PORT/$KS_FILE inst.text console=ttyS0,115200n8"
log "   - Press Ctrl+X to boot."
log ""
log "2. After boot, you do NOT need VNC anymore."
log "   - Monitor installation progress in the serial log:"
log "       tail -f $SERIAL_LOG"
log "   - Watch for Kickstart requests in the HTTP log:"
log "       tail -f $HTTP_LOG"
log ""
log "3. When installation is done, SSH into your new server:"
log "   ssh -p $HOST_SSH_PORT dlesieur@localhost"
log ""
log "=================================="
log "If you do not see output in the serial log, check the VNC console for installer progress."
log "You do NOT need a graphical desktop for the server install."
log "=================================="
sleep 2

# Monitor both serial and HTTP logs
TAIL_PID=""
(tail -f "$SERIAL_LOG" 2>/dev/null | while IFS= read -r line; do
    echo "[SERIAL] $line"
    # Detect if installer has started
    if [[ "$line" =~ "Starting installer" ]] || [[ "$line" =~ "anaconda" ]]; then
        echo "*** INSTALLER DETECTED - Installation in progress ***"
    fi
done) &
TAIL_PID=$!

sleep 2
echo ""
echo "=== HTTP Server Access Log (Kickstart requests will appear here) ==="
tail -f "$HTTP_LOG" | while IFS= read -r line; do
    echo "[HTTP] $line"
    # Detect Kickstart fetch
    if [[ "$line" =~ "GET /ks.cfg" ]]; then
        echo "*** KICKSTART FETCHED - Automated installation running! ***"
    fi
done

log "NOTE:"
log "  - The serial log (/tmp/vbox-${VM_NAME}-serial.log) will only show output AFTER the kernel boots with 'console=ttyS0,115200n8'."
log "  - To see the GRUB menu and early boot, use the VNC console (localhost:3389) as described above."
log "  - Once the installer starts, you can monitor progress in the serial log."
log ""
log "If you do not see output in the serial log, check the VNC console for installer progress."
log ""
log "TIP:"
log "  If you cannot connect with VNC, try starting the VM with:"
log "    VBoxManage startvm \"$VM_NAME\" --type separate"
log "  This will ensure the VM display is available for VRDE/VNC."
log ""

log ""
log "=================================="
log "DEBUGGING STEPS IF NOTHING HAPPENS"
log "=================================="
log "1. Is the VM running?"
VBoxManage showvminfo "$VM_NAME" | grep -E "State|VRDE"
log ""
log "2. Is the ISO attached?"
VBoxManage showvminfo "$VM_NAME" | grep -A 5 "Storage"
log ""
log "3. Is VRDE active? (Should say 'VRDE Connection: active' after VNC connects)"
VBoxManage showvminfo "$VM_NAME" | grep "VRDE Connection"
log ""
log "4. Is the HTTP server reachable from your host?"
log "   Try: curl http://localhost:$HTTP_PORT/ks.cfg"
log ""
log "5. Is the HTTP server reachable from the guest?"
log "   If you can get to a shell in the VM, try: curl http://10.0.2.2:$HTTP_PORT/ks.cfg"
log ""
log "6. Is the serial log file being created and updated?"
log "   ls -l $SERIAL_LOG"
log "   tail -n 20 $SERIAL_LOG"
log ""
log "7. Did you interact with the GRUB menu via VNC?"
log "   - You MUST use VNC to edit the boot parameters and start the install."
log ""
log "If any of these checks fail, please copy the output and ask for help."
log "=================================="
