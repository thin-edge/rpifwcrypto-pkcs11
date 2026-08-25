#!/bin/sh
# -------------------------------------------
# Check the glibc version the binaries require
# -------------------------------------------
# A dynamically linked binary works on any glibc that is at least as new as
# the highest versioned symbol it references (glibc symbol versioning), so the
# build image silently decides the oldest distribution the packages support.
# Building in a newer image is easy to do by accident and the resulting
# package still installs -- it only fails at runtime with
# "version `GLIBC_2.xx' not found".
#
# This fails the build if any of the given binaries needs a glibc newer than
# MAX_GLIBC. Binaries with no versioned glibc references (a musl build, for
# example) are simply reported as such.
#
# Usage:
#     ci/check-glibc.sh <binary> [<binary>...]
#
# Environment:
#     MAX_GLIBC   Highest glibc version the binaries may require.
#                 Default 2.28 = Debian 10, Ubuntu 18.04, RHEL 8.
set -eu

MAX_GLIBC="${MAX_GLIBC:-2.28}"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <binary> [<binary>...]" >&2
    exit 1
fi

dump_versions() {
    # readelf is in binutils, which any toolchain that built these has
    readelf --wide --dyn-syms "$1" 2>/dev/null | grep -o 'GLIBC_[0-9][0-9.]*' | sort -u
}

# Compare dotted versions as numbers, e.g. 2.34 -> 2034, 2.9 -> 2009
as_number() {
    echo "$1" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}'
}

max_allowed=$(as_number "$MAX_GLIBC")
status=0

for binary in "$@"; do
    if [ ! -f "$binary" ]; then
        echo "$binary: not found" >&2
        exit 1
    fi

    highest=""
    highest_number=0
    for version in $(dump_versions "$binary"); do
        number=$(as_number "${version#GLIBC_}")
        if [ "$number" -gt "$highest_number" ]; then
            highest_number="$number"
            highest="${version#GLIBC_}"
        fi
    done

    if [ -z "$highest" ]; then
        echo "$binary: no versioned glibc references (static or non-glibc build)"
        continue
    fi

    if [ "$highest_number" -gt "$max_allowed" ]; then
        echo "$binary: requires glibc $highest, which is newer than the supported baseline $MAX_GLIBC" >&2
        echo "  the symbols forcing this are:" >&2
        readelf --wide --dyn-syms "$binary" | grep "GLIBC_$highest" | awk '{print "    " $8}' | sort -u >&2
        echo "  build in an older image, or raise MAX_GLIBC if the baseline really has moved" >&2
        status=1
    else
        echo "$binary: requires glibc $highest (baseline $MAX_GLIBC)"
    fi
done

exit "$status"
