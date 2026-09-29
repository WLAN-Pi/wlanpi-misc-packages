#!/bin/bash
# Checks every vendored package ships its apt pin. Run: tests/test-apt-pins.sh

root="$(dirname "$(readlink -f "$0")")/.."
fail=0

expected_pref() {
    cat <<EOF
Explanation: Keep the WLAN Pi build of $1, even when Debian's version is
Explanation: higher. Debian's build lacks the WLAN Pi patches, units and
Explanation: config. Shipped by wlanpi-misc-packages.
Package: $1
Pin: release o=packagecloud.io/wlanpi/main
Pin-Priority: 990

Package: $1
Pin: release o=packagecloud.io/wlanpi/dev
Pin-Priority: 990
EOF
}

for conf in "${root}"/*.conf; do
    pkg="$(basename "${conf}" .conf)"
    # Not in Debian, so nothing can replace it.
    [ "${pkg}" = "wlanpi-linux-firmware" ] && continue
    dir="${root}/debians/${pkg}"
    ok=1
    if ! cmp -s <(expected_pref "${pkg}") "${dir}/wlanpi-${pkg}.pref"; then
        echo "FAIL ${pkg}: debians/${pkg}/wlanpi-${pkg}.pref differs from the expected pin"
        ok=0
    fi
    if ! grep -qx "debian/wlanpi-${pkg}.pref etc/apt/preferences.d/" "${dir}/${pkg}.install" 2>/dev/null; then
        echo "FAIL ${pkg}: debians/${pkg}/${pkg}.install doesn't install the pin"
        ok=0
    fi
    if [ "${ok}" = 1 ]; then echo "ok   ${pkg}"; else fail=1; fi
done

exit "${fail}"
