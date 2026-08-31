#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
    echo "Usage: $0 VERSION"
    echo "Example: $0 0.1.0"
    exit 64
fi

version="$1"
build_number="${BUILD_NUMBER:-1}"
developer_team="HT5B666N35"
notary_profile="${NOTARY_PROFILE:-SPDFV-notary}"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${OUTPUT_DIR:-$project_root/dist}"
archive_path="$output_dir/SPDFV.xcarchive"
export_path="$output_dir/export"
dmg_name="SPDFV-$version.dmg"
dmg_path="$output_dir/$dmg_name"
checksum_path="$dmg_path.sha256"
export_options="$project_root/Scripts/ExportOptions-DeveloperID.plist"
release_tmp="$(mktemp -d "${TMPDIR:-/tmp}/spdfv-release.XXXXXX")"
staging_dir="$release_tmp/SPDFV"

cleanup() {
    local exit_status=$?
    trap - EXIT
    rm -rf "$release_tmp"
    exit "$exit_status"
}
trap cleanup EXIT

for required_tool in xcodebuild codesign hdiutil security spctl shasum xcrun; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        echo "Missing required tool: $required_tool"
        exit 69
    fi
done

developer_identity="${DEVELOPER_ID_APPLICATION:-}"
if [[ -z "$developer_identity" ]]; then
    developer_identity="$(
        security find-identity -v -p codesigning \
            | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
            | head -n 1
    )"
fi
if [[ -z "$developer_identity" ]]; then
    echo "No Developer ID Application certificate is available in the login keychain."
    echo "Create or install one in Xcode before producing a public build."
    exit 78
fi

if ! xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1; then
    echo "Notarization profile '$notary_profile' is unavailable."
    echo "Create it once with: xcrun notarytool store-credentials '$notary_profile'"
    exit 78
fi

if [[ -e "$archive_path" || -e "$export_path" || -e "$dmg_path" || -e "$checksum_path" ]]; then
    echo "Release output already exists in $output_dir. Move it aside before rebuilding."
    exit 73
fi

mkdir -p "$output_dir" "$staging_dir"

echo "Archiving SPDFV $version ($build_number)…"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild \
    -project "$project_root/SPDFV.xcodeproj" \
    -scheme SPDFV \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive_path" \
    DEVELOPMENT_TEAM="$developer_team" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    archive

echo "Exporting with Developer ID…"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates

app_path="$export_path/SPDFV.app"
if [[ ! -d "$app_path" ]]; then
    echo "Export did not produce $app_path"
    exit 70
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
cp -R "$app_path" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

echo "Creating and signing ${dmg_name}…"
hdiutil create \
    -volname "SPDFV $version" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    "$dmg_path"
codesign --force --timestamp --sign "$developer_identity" "$dmg_path"
codesign --verify --verbose=2 "$dmg_path"

echo "Submitting $dmg_name to Apple notarization…"
xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"

(
    cd "$output_dir"
    shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)

if [[ "${GENERATE_SPARKLE_APPCAST:-1}" == "1" ]]; then
    bash "$project_root/Scripts/generate_appcast.sh" "$version" "$dmg_path"
else
    echo "Skipping Sparkle appcast generation."
fi

echo "Release artifact ready: $dmg_path"
echo "Checksum: $checksum_path"
