#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${1:-rhl}"

log() { echo "[*] $*"; }

log "Stopping VM '$VM_NAME'..."
VBoxManage controlvm "$VM_NAME" acpipowerbutton 2>/dev/null || \
VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true

sleep 2

log "Cleaning up..."
rm -f "/tmp/vbox-${VM_NAME}-serial.log"
rm -f "/tmp/vbox-http-server.log"

# Kill HTTP server if running on port 8080
if lsof -ti :8080 >/dev/null 2>&1; then
    log "Stopping HTTP server..."
    lsof -ti :8080 | xargs -r kill 2>/dev/null || true
fi

# Kill any Python HTTP servers from this directory
pkill -f "python3 -m http.server 8080" 2>/dev/null || true

log "VM stopped and cleaned up"
log ""
log "To restart: ./start_vm.sh"
log "To SSH (after install): ssh -p 4242 dlesieur@localhost"
