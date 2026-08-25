#!/bin/bash
# -----------------------------------------------
# Publish packages to Cloudsmith.io
# -----------------------------------------------
# Uploads the deb/rpm/apk packages produced by ci/build.sh to a Cloudsmith
# package repository. The cloudsmith CLI is installed on demand if missing.
help() {
  cat <<EOF
Publish packages from a path to a package repository

All the necessary dependencies will be downloaded automatically if they are not already present

Usage:
    $0 [<path>]

Flags:
    --token <string>            Cloudsmith API key used to authenticate the commands
    --owner <string>            Cloudsmith repository owner (default: thinedge)
    --repo <string>             Cloudsmith repository to publish to (default: community)
    --path <dir>                Directory to look for packages in (default: ./)
    --help|-h                   Show this help

Optional Environment variables (instead of flags)

PUBLISH_TOKEN            Equivalent to --token flag
PUBLISH_OWNER            Equivalent to --owner flag
PUBLISH_REPO             Equivalent to --repo flag

Examples:
    $0 ./dist --token "mywonderfultoken" --repo "community"

    \$ Publish all debian/alpine/rpm packages found under ./dist
EOF
}

PUBLISH_TOKEN="${PUBLISH_TOKEN:-}"
PUBLISH_OWNER="${PUBLISH_OWNER:-thinedge}"
PUBLISH_REPO="${PUBLISH_REPO:-community}"
SOURCE_PATH="./"

#
# Argument parsing
#
POSITIONAL=()
while [[ $# -gt 0 ]]
do
    case "$1" in
        # Repository owner
        --owner)
            if [ -n "$2" ]; then PUBLISH_OWNER="$2"; fi
            shift
            ;;

        # Token used to authenticate publishing commands
        --token)
            PUBLISH_TOKEN="$2"
            shift
            ;;

        # Where to look for the packages to publish
        --path)
            SOURCE_PATH="$2"
            shift
            ;;

        # Which repo to publish to (under the given owner)
        --repo)
            if [ -n "$2" ]; then PUBLISH_REPO="$2"; fi
            shift
            ;;

        --help|-h)
            help
            exit 0
            ;;

        -*)
            echo "Unrecognized flag: $1" >&2
            help
            exit 1
            ;;

        *)
            POSITIONAL+=("$1")
            ;;
    esac
    shift
done
set -- "${POSITIONAL[@]}"

if [ $# -gt 0 ]; then
    SOURCE_PATH="$1"
fi

if [ -z "$PUBLISH_TOKEN" ]; then
    echo "Missing required Cloudsmith API key (--token or PUBLISH_TOKEN)" >&2
    exit 1
fi

# Add local tools path
LOCAL_TOOLS_PATH="$HOME/.local/bin"
export PATH="$LOCAL_TOOLS_PATH:$PATH"

# Install tooling if missing
if ! [ -x "$(command -v cloudsmith)" ]; then
    echo 'Install cloudsmith cli' >&2
    if command -v pip3 &>/dev/null; then
        pip3 install --upgrade cloudsmith-cli
    elif command -v pip &>/dev/null; then
        pip install --upgrade cloudsmith-cli
    else
        echo "Could not install cloudsmith cli. Reason: pip3/pip is not installed" >&2
        exit 2
    fi
fi

publish() {
    local sourcedir="$1"
    local pattern="$2"
    local package_type="$3"
    local distribution="$4"
    local distribution_version="$5"

    # Notes: Currently Cloudsmith does not support the following (this might change in the future)
    #  * distribution and distribution_version must be selected from values in the list. use `cloudsmith list distros` to get the list
    #  * The component can not be set and is currently fixed to 'main'
    find "$sourcedir" -name "$pattern" -print0 | while read -r -d $'\0' file
    do
        echo "Publishing: $file" >&2
        cloudsmith upload "$package_type" "${PUBLISH_OWNER}/${PUBLISH_REPO}/${distribution}/${distribution_version}" "$file" \
            --no-wait-for-sync \
            --api-key "${PUBLISH_TOKEN}"
    done
}

publish "$SOURCE_PATH" "*.deb" deb "any-distro" "any-version"
publish "$SOURCE_PATH" "*.rpm" rpm "any-distro" "any-version"
publish "$SOURCE_PATH" "*.apk" alpine "alpine" "any-version"
