# wlanpi-misc-packages

Packaging miscellaneous binaries, like firmware and iw. Goal is to have a package with newer code than the ones currently available from official repositories.

## Versioning

`package.sh` sets the version; don't hand-edit the changelogs. Versions are `<upstream>+wlanpi-<N>`, a WLAN Pi convention. A new upstream starts at `+wlanpi-1`, and a rebuild of the same upstream bumps `<N>` (`3.21+wlanpi-1` → `3.21+wlanpi-2`). Epochs carry over.

The `+wlanpi` marker is part of the upstream version, the way Debian marks repacked sources with `+dfsg`. That makes our build sort above Debian's builds of the same upstream: binary rebuilds (`-1+b1`), non-maintainer uploads (`-1.1`) and repacks (`+dfsg-1`). A newer upstream from Debian still sorts higher. Versions before this convention were `<upstream>-<M>wlanpi<N>`; each package moves to `+wlanpi-1` at its next build. `tests/test-next-package-version.sh` checks all of this.

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