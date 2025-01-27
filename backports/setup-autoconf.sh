#!/bin/bash
set -e

# Function to compare version numbers
version_greater_equal() {
    printf '%s\n' "$1" "$2" | sort -C -V
    return $?
}

# Check if we need to install autoconf 2.71
if command -v autoconf >/dev/null 2>&1; then
    current_version=$(autoconf --version | head -n1 | awk '{print $NF}')
    if version_greater_equal "$current_version" "2.71"; then
        echo "autoconf $current_version is already installed in chroot"
        exit 0
    fi
fi

echo "Building and installing autoconf 2.71 in chroot"
cd /tmp/backports
./build-autoconf.sh
dpkg -i autoconf-2.71*.deb || apt-get install -f -y