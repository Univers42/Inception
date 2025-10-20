if [ -x "$(command -v VBoxManage)" ]; then
    echo "VirtualBox is installed."
else
    echo "VirtualBox is not installed. Please install VirtualBox to proceed."
    echo
fi
