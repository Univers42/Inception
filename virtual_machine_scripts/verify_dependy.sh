#!/usr/bin/env bash

echo "=== Checking dependencies ==="

# Check VirtualBox
if command -v VBoxManage >/dev/null 2>&1; then
    echo "✓ VirtualBox is installed ($(VBoxManage --version))"
else
    echo "✗ VirtualBox is not installed. Please install VirtualBox to proceed."
    exit 1
fi

# Check socat
if command -v socat >/dev/null 2>&1; then
    echo "✓ socat is installed"
else
    echo "✗ socat is not installed. Installing..."
    sudo apt install -y socat
fi

# Check Python3
if command -v python3 >/dev/null 2>&1; then
    echo "✓ Python3 is installed ($(python3 --version))"
else
    echo "✗ Python3 is not installed."
    exit 1
fi

# Check if port 8080 is in use
echo ""
echo "=== Checking port availability ==="
if lsof -i :8080 >/dev/null 2>&1; then
    echo "⚠ Port 8080 is already in use:"
    lsof -i :8080
    echo ""
    read -p "Kill the process using port 8080? (y/n): " kill_proc
    if [[ $kill_proc =~ ^[yY]$ ]]; then
        sudo lsof -ti :8080 | xargs -r sudo kill -9
        echo "✓ Port 8080 freed"
    else
        echo "! You may need to use a different port or manually kill the process"
    fi
else
    echo "✓ Port 8080 is available"
fi

echo ""
echo "=== All checks complete ==="