# wlanpi-misc-packages

Packaging miscellaneous binaries, like firmware and iw. Goal is to have a package with newer code than the ones currently available from official repositories.

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