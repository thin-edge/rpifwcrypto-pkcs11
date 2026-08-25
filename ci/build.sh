#!/bin/sh
# -------------------------------------------
# Build the module and the linux packages
# -------------------------------------------
# Compiles rpifwcrypto-pkcs11 for the machine it runs on and packages it with
# nfpm. The module and the rpi-fw-crypto CLI link against the system libc, so
# they have to be built against the libc they will run on: one glibc build
# covers the deb and rpm packages, and a second musl build is needed for the
# apk package (a glibc shared object cannot be dlopen()ed by musl's loader).
# The release workflow therefore calls this script twice, once in a Debian
# container with PACKAGERS="deb rpm" and once in an Alpine container with
# PACKAGERS=apk, both writing into the same ./dist directory.
#
# Usage:
#     ci/build.sh [<semver>]
#
# Environment:
#     SEMVER      Package version, e.g. 1.0.0 (default: derived from git)
#     ARCH        Package architecture (default: arm64)
#     PACKAGERS   Space separated nfpm packagers (default: "deb rpm apk")
#     MAX_GLIBC   Oldest glibc the packages must work on (see ci/check-glibc.sh)
set -eu

if [ $# -gt 0 ]; then
    SEMVER="$1"
fi

if [ -z "${SEMVER:-}" ]; then
    SEMVER=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
    SEMVER="${SEMVER}-dev.$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

# Tags are usually written as v1.2.3, package versions are not
SEMVER="${SEMVER#v}"
ARCH="${ARCH:-arm64}"
PACKAGERS="${PACKAGERS:-deb rpm apk}"
export SEMVER ARCH

echo "Using version: $SEMVER (arch: $ARCH)"

if ! command -v nfpm >/dev/null 2>&1; then
    echo "nfpm is not installed. See https://nfpm.goreleaser.com/install/" >&2
    exit 2
fi

# Only the build tree and the staged payload are cleaned: packages built by a
# previous invocation (for a different libc) are kept.
rm -rf build dist/pkgroot
mkdir -p dist/pkgroot/usr/lib/pkcs11 dist/pkgroot/usr/bin

cmake -B build -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DPKCS11_MODULE_DIR=lib/pkcs11
cmake --build build

# Copy the versioned library out of the build directory under its plain name
# (-L dereferences the rpifwcrypto-pkcs11.so symlink). A PKCS#11 module is
# dlopen()ed by name, so the soname symlinks are not shipped.
cp -L build/rpifwcrypto-pkcs11.so dist/pkgroot/usr/lib/pkcs11/rpifwcrypto-pkcs11.so
strip --strip-unneeded dist/pkgroot/usr/lib/pkcs11/rpifwcrypto-pkcs11.so 2>/dev/null || true

# Raspberry Pi's rpi-fw-crypto CLI (used to provision the OTP key) is built
# from the raspi-utils submodule alongside the module.
RPI_FW_CRYPTO=$(find build -name rpi-fw-crypto -type f | head -n 1)
if [ -z "$RPI_FW_CRYPTO" ]; then
    echo "rpi-fw-crypto was not built. Is the 3rdparty/raspi-utils submodule checked out?" >&2
    exit 1
fi
cp "$RPI_FW_CRYPTO" dist/pkgroot/usr/bin/rpi-fw-crypto
strip --strip-unneeded dist/pkgroot/usr/bin/rpi-fw-crypto 2>/dev/null || true

# Guard against building in an image whose glibc is newer than the oldest
# distribution release the packages are meant to support.
echo ""
ci/check-glibc.sh \
    dist/pkgroot/usr/lib/pkcs11/rpifwcrypto-pkcs11.so \
    dist/pkgroot/usr/bin/rpi-fw-crypto

for package_type in $PACKAGERS; do
    echo ""
    nfpm package --packager "$package_type" --target ./dist/
done

echo ""
echo "Created packages:"
for package in dist/*.deb dist/*.rpm dist/*.apk; do
    [ -f "$package" ] && ls -l "$package" || true
done
