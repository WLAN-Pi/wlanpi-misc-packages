# wlanpi-misc-packages

Packaging miscellaneous binaries, like firmware and iw. Goal is to have a package with newer code than the ones currently available from official repositories.

## Versioning

`package.sh` sets the version; don't hand-edit the changelogs. Versions are `<upstream>+wlanpi-<N>`, a WLAN Pi convention. A new upstream starts at `+wlanpi-1`, and a rebuild of the same upstream bumps `<N>` (`3.21+wlanpi-1` → `3.21+wlanpi-2`). Epochs carry over.

The `+wlanpi` marker is part of the upstream version, the way Debian marks repacked sources with `+dfsg`. That makes our build sort above Debian's builds of the same upstream: binary rebuilds (`-1+b1`), non-maintainer uploads (`-1.1`) and repacks (`+dfsg-1`). A newer upstream from Debian still sorts higher. Versions before this convention were `<upstream>-<M>wlanpi<N>`; each package moves to `+wlanpi-1` at its next build. `tests/test-next-package-version.sh` checks all of this.

## Apt Pins

Each package we rebuild from Debian (all except `wlanpi-linux-firmware`) ships `/etc/apt/preferences.d/wlanpi-<pkg>.pref`. It pins the package to the `wlanpi/main` and `wlanpi/dev` packagecloud repos at priority 990, so apt keeps our build even when Debian publishes a higher version, including a newer upstream. Debian's builds lack our patches, units and ufw rules. At 990 apt never downgrades on its own. The pin ships with the package, so every release can update it, and purging the package removes it. `tests/test-apt-pins.sh` checks that every package in a `*.conf` has one.

Security fixes for these packages are ours to ship. Debian's don't reach devices: our builds already sort above Debian's security updates, which patch Debian's older upstream (such as `2:2.10-24+deb13u1`), and the pin keeps it that way. Watch upstream advisories, starting with <https://w1.fi/security/> for hostapd and wpasupplicant. The Debian security tracker entries for `wpa`, `iperf`, `iperf3`, `iw` and `wavemon` are also worth checking. When a fix lands, rebuild on a newer upstream ref, or add the fix commit to `debians/<pkg>/patches` while `package_ref` is still a release tag.

## Testing

### Local

```
# Build a specific package
./package.sh --package iperf2

# Force clean rebuild
./package.sh --clean --force-sync --package iperf3

# Build all packages
./package.sh --all
```

Depends

```
sudo apt-get update
sudo apt-get install -y \
    devscripts \
    build-essential \
    sbuild \
    schroot \
    debootstrap \
    qemu-user-static
```