#!/bin/bash
# backports/build-autoconf.sh

set -e

AUTOCONF_VERSION="2.71"
AUTOCONF_DIR="autoconf-${AUTOCONF_VERSION}"
AUTOCONF_TAR="autoconf-${AUTOCONF_VERSION}.tar.gz"
AUTOCONF_URL="https://ftp.gnu.org/gnu/autoconf/${AUTOCONF_TAR}"

# Download and extract autoconf if needed
if [ ! -d "${AUTOCONF_DIR}" ]; then
    wget -N "${AUTOCONF_URL}"
    tar xf "${AUTOCONF_TAR}"
    cp -r debian "${AUTOCONF_DIR}/"
fi

# Build autoconf package
cd "${AUTOCONF_DIR}"
dpkg-buildpackage -us -uc

# Install the package
cd ..
dpkg -i autoconf-${AUTOCONF_VERSION}_*.deb || true
apt-get install -f