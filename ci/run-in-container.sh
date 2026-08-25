#!/bin/sh
# -------------------------------------------
# Run ci/build.sh inside a container
# -------------------------------------------
# The packages have to be built against the libc they will run on, so the
# release workflow builds them in containers rather than on the runner itself.
# The nfpm binary from the host is mounted into the container (it is a static
# Go binary, so it runs on glibc and musl alike) to avoid installing the Go
# toolchain in every image.
#
# Usage:
#     ci/run-in-container.sh <image> <setup-command>
#
# Example:
#     PACKAGERS="deb rpm" ci/run-in-container.sh debian:bookworm \
#         'apt-get update && apt-get install -y build-essential cmake libgnutls28-dev'
#
# SEMVER, ARCH, PACKAGERS and MAX_GLIBC are passed through to ci/build.sh.
set -eu

if [ $# -lt 2 ]; then
    echo "Usage: $0 <image> <setup-command>" >&2
    exit 1
fi

IMAGE="$1"
SETUP="$2"

NFPM=$(command -v nfpm || true)
if [ -z "$NFPM" ]; then
    echo "nfpm is not installed. See https://nfpm.goreleaser.com/install/" >&2
    exit 2
fi

echo "Building in $IMAGE (packagers: ${PACKAGERS:-deb rpm apk})"

docker run --rm \
    -v "$PWD:/src" \
    -v "$NFPM:/usr/local/bin/nfpm:ro" \
    -w /src \
    -e SEMVER -e ARCH -e PACKAGERS -e MAX_GLIBC \
    "$IMAGE" \
    sh -c "$SETUP && ci/build.sh"
