#!/bin/bash
# Checks next_package_version in package.sh. Run: tests/test-next-package-version.sh

# shellcheck source=../package.sh
source "$(dirname "$(readlink -f "$0")")/../package.sh"

fail=0

expect() {
    local current="$1" upstream="$2" want="$3" got
    got="$(next_package_version "${current}" "${upstream}" 2>/dev/null)" || got="<error>"
    if [ "${got}" = "${want}" ]; then
        echo "ok   ${current} + ${upstream} = ${got}"
    else
        echo "FAIL ${current} + ${upstream}: want ${want}, got ${got}"
        fail=1
    fi
}

sorts() {
    if dpkg --compare-versions "$1" "$2" "$3"; then
        echo "ok   $1 $2 $3"
    else
        echo "FAIL $1 $2 $3"
        fail=1
    fi
}

# Rebuilds and new upstreams
expect "3.21+wlanpi-1" "3.21" "3.21+wlanpi-2"
expect "3.21+wlanpi-9" "3.21" "3.21+wlanpi-10"
expect "3.21+wlanpi-2" "3.22" "3.22+wlanpi-1"
expect "2:2.12+wlanpi-1" "2.12" "2:2.12+wlanpi-2"
expect "2:2.12+wlanpi-1" "2.13" "2:2.13+wlanpi-1"
expect "1.0-rc1+wlanpi-1" "1.0-rc1" "1.0-rc1+wlanpi-2"
# Switch-over from the old <M>wlanpi<N> format
expect "3.21-2wlanpi1" "3.21" "3.21+wlanpi-1"
expect "2:2.12-3wlanpi1" "2.12" "2:2.12+wlanpi-1"
expect "1.20260702-1wlanpi1" "1.20260702" "1.20260702+wlanpi-1"
expect "1.20260702-1wlanpi1" "1.20260801" "1.20260801+wlanpi-1"
# Errors
expect "3.21+wlanpi-2" "3.20" "<error>"
expect "3.21-2wlanpi1" "3.20" "<error>"
expect "3.21+wlanpi-x" "3.21" "<error>"

# Beats Debian's builds of the same upstream, loses to a newer upstream
sorts "6.17+wlanpi-1" gt "6.17-1+b1"
sorts "3.21+wlanpi-1" gt "3.21-5.1"
sorts "2.2.2+wlanpi-1" gt "2.2.2+dfsg-3"
sorts "2.2.2+wlanpi-1" gt "2.2.2+ds1-1"
sorts "2:2.12+wlanpi-1" gt "2:2.12-3+deb13u1"
sorts "2.2.2+wlanpi-1" lt "2.2.3-1"
sorts "2.2.2+wlanpi-1" lt "2.2.2.1-1"
sorts "6.17+wlanpi-1" lt "6.18~rc1-1"

exit "${fail}"
