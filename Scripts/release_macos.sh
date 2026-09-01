#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ || ( $# -eq 2 && "$2" != "--dry-run" ) ]]; then
    echo "Usage: $0 VERSION [--dry-run]"
    echo "Example: $0 0.1.3 --dry-run"
    exit 64
fi

version="$1"
dry_run=0
if [[ "${2:-}" == "--dry-run" ]]; then dry_run=1; fi
developer_team="${DEVELOPER_TEAM:-HT5B666N35}"
notary_profile="${NOTARY_PROFILE:-SPDFV-notary}"
project_root="$(cd "$(dirname "$0")/.." && pwd)"
project_file="$project_root/SPDFV.xcodeproj/project.pbxproj"
appcast_path="$project_root/Updates/appcast.xml"
current_version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' "$project_file" | head -n 1)"
current_build="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\);/\1/p' "$project_file" | head -n 1)"
if [[ ! "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ || ! "$current_build" =~ ^[1-9][0-9]*$ ]]; then
    echo "Could not read a valid app version and build from $project_file"
    exit 70
fi
build_number="${BUILD_NUMBER:-$((current_build + 1))}"
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

for required_tool in xcodebuild git sed swift; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        echo "Missing required tool: $required_tool"
        exit 69
    fi
done

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "BUILD_NUMBER must be a positive integer: $build_number"
    exit 64
fi
if (( build_number <= current_build )); then
    echo "Build number $build_number must be greater than project build $current_build."
    exit 64
fi

version_base="${version%%-*}"
current_base="${current_version%%-*}"
IFS=. read -r version_major version_minor version_patch <<< "$version_base"
IFS=. read -r current_major current_minor current_patch <<< "$current_base"
version_key=$((version_major * 100000000 + version_minor * 10000 + version_patch))
current_key=$((current_major * 100000000 + current_minor * 10000 + current_patch))
if (( version_key <= current_key )); then
    echo "Release version $version must be greater than project version $current_version."
    exit 64
fi

if [[ -f "$appcast_path" ]]; then
    if grep -q "<sparkle:shortVersionString>$version</sparkle:shortVersionString>" "$appcast_path"; then
        echo "Version $version already exists in the Sparkle appcast."
        exit 64
    fi
    appcast_builds="$(sed -n 's|.*<sparkle:version>\([0-9][0-9]*\)</sparkle:version>.*|\1|p' "$appcast_path")"
    while IFS= read -r published_build; do
        if [[ -n "$published_build" ]] && (( build_number <= published_build )); then
            echo "Build number $build_number must be greater than published build $published_build."
            exit 64
        fi
    done <<< "$appcast_builds"
fi

if [[ "${ALLOW_DIRTY:-0}" != "1" ]] && [[ -n "$(git -C "$project_root" status --porcelain)" ]]; then
    echo "The worktree must be clean before a release. Commit or stash pending changes."
    echo "Set ALLOW_DIRTY=1 only for a local rehearsal."
    exit 65
fi

xcode_developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

run_validation() {
    echo "Running release validation gates…"
    bash "$project_root/Scripts/audit_visual_assets.sh"
    DEVELOPER_DIR="$xcode_developer_dir" swift test --package-path "$project_root/Core"
    DEVELOPER_DIR="$xcode_developer_dir" swift test --package-path "$project_root/CLI"
    DEVELOPER_DIR="$xcode_developer_dir" xcodebuild \
        -project "$project_root/SPDFV.xcodeproj" \
        -scheme SPDFV \
        -configuration Debug \
        -destination 'platform=macOS' \
        -parallel-testing-enabled NO \
        -only-testing:SPDFVTests \
        CODE_SIGNING_ALLOWED=NO \
        test
    DEVELOPER_DIR="$xcode_developer_dir" xcodebuild \
        -project "$project_root/SPDFV.xcodeproj" \
        -scheme SPDFV \
        -configuration Debug \
        -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO \
        build-for-testing
}

verify_app_bundle() {
    local candidate="$1"
    local info_plist="$candidate/Contents/Info.plist"
    local bundled_version bundled_build feed_url public_key
    if [[ ! -d "$candidate" || ! -f "$info_plist" ]]; then
        echo "Release build did not produce a complete app bundle: $candidate"
        exit 70
    fi
    bundled_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
    bundled_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
    feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info_plist")"
    public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist")"
    if [[ "$bundled_version" != "$version" || "$bundled_build" != "$build_number" ]]; then
        echo "Bundle version mismatch: expected $version ($build_number), found $bundled_version ($bundled_build)."
        exit 70
    fi
    if [[ "$feed_url" != https://* || -z "$public_key" ]]; then
        echo "Sparkle feed URL or public key is missing from the built app."
        exit 70
    fi
    if [[ ! -x "$candidate/Contents/Resources/SPDFVQueueRunner" ]]; then
        echo "The embedded queue runner is missing or not executable."
        exit 70
    fi
    if [[ ! -d "$candidate/Contents/Frameworks/Sparkle.framework" ]]; then
        echo "Sparkle.framework is missing from the built app."
        exit 70
    fi
}

if [[ "${RUN_TESTS:-1}" == "1" ]]; then
    run_validation
else
    echo "Skipping release validation because RUN_TESTS=0."
fi

if (( dry_run == 1 )); then
    rehearsal_derived_data="$release_tmp/DerivedData"
    echo "Building unsigned release rehearsal for SPDFV $version ($build_number)…"
    DEVELOPER_DIR="$xcode_developer_dir" xcodebuild \
        -project "$project_root/SPDFV.xcodeproj" \
        -scheme SPDFV \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$rehearsal_derived_data" \
        CODE_SIGNING_ALLOWED=NO \
        MARKETING_VERSION="$version" \
        CURRENT_PROJECT_VERSION="$build_number" \
        build
    verify_app_bundle "$rehearsal_derived_data/Build/Products/Release/SPDFV.app"
    echo "Release rehearsal passed for SPDFV $version ($build_number)."
    echo "No archive, signature, notarization submission, appcast, or dist artifact was created."
    exit 0
fi

for required_tool in codesign hdiutil security spctl shasum xcrun; do
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
DEVELOPER_DIR="$xcode_developer_dir" \
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
DEVELOPER_DIR="$xcode_developer_dir" \
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

verify_app_bundle "$app_path"
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
