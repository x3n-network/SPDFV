#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
    echo "Usage: $0 VERSION DMG_PATH"
    echo "Example: $0 0.1.2 dist/SPDFV-0.1.2.dmg"
    exit 64
fi

version="$1"
dmg_path="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
appcast_path="${APPCAST_PATH:-$project_root/Updates/appcast.xml}"
key_account="${SPARKLE_KEY_ACCOUNT:-x3n-network}"
download_url_prefix="https://github.com/x3n-network/SPDFV/releases/download/v$version/"
release_url="https://github.com/x3n-network/SPDFV/releases/tag/v$version"

if [[ ! -f "$dmg_path" ]]; then
    echo "Update archive not found: $dmg_path"
    exit 66
fi
if [[ "$(basename "$dmg_path")" != "SPDFV-$version.dmg" ]]; then
    echo "Update archive must be named SPDFV-$version.dmg"
    exit 64
fi

generate_appcast="${SPARKLE_GENERATE_APPCAST:-}"
if [[ -z "$generate_appcast" ]]; then
    derived_data_root="${XCODE_DERIVED_DATA_ROOT:-$HOME/Library/Developer/Xcode/DerivedData}"
    while IFS= read -r candidate; do
        generate_appcast="$candidate"
        break
    done < <(find "$derived_data_root" -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' -type f -print)
fi

if [[ -z "$generate_appcast" || ! -x "$generate_appcast" ]]; then
    echo "Sparkle's generate_appcast tool was not found."
    echo "Resolve the Sparkle package in Xcode or set SPARKLE_GENERATE_APPCAST."
    exit 69
fi

appcast_tmp="$(mktemp -d "${TMPDIR:-/tmp}/spdfv-appcast.XXXXXX")"
cleanup() {
    local exit_status=$?
    trap - EXIT
    rm -rf "$appcast_tmp"
    exit "$exit_status"
}
trap cleanup EXIT

cp "$dmg_path" "$appcast_tmp/"
if [[ -f "$appcast_path" ]]; then
    cp "$appcast_path" "$appcast_tmp/appcast.xml"
fi

"$generate_appcast" \
    --account "$key_account" \
    --download-url-prefix "$download_url_prefix" \
    --link "$release_url" \
    --maximum-versions 3 \
    --maximum-deltas 0 \
    -o "$appcast_tmp/appcast.xml" \
    "$appcast_tmp"

if ! grep -q "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" "$appcast_tmp/appcast.xml"; then
    echo "Generated appcast does not contain version $version."
    exit 70
fi
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$appcast_tmp/appcast.xml"
fi

mkdir -p "$(dirname "$appcast_path")"
pending_appcast="$appcast_path.pending"
cp "$appcast_tmp/appcast.xml" "$pending_appcast"
mv "$pending_appcast" "$appcast_path"

echo "Sparkle appcast updated: $appcast_path"
