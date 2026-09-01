#!/bin/bash

set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--release" ) ]]; then
    echo "Usage: $0 [--release]"
    exit 64
fi

project_root="$(cd "$(dirname "$0")/.." && pwd)"
xcode_developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
package_configuration="debug"
if [[ "${1:-}" == "--release" ]]; then package_configuration="release"; fi

for required_tool in git swift xcodebuild; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        echo "Missing required tool: $required_tool"
        exit 69
    fi
done

echo "Auditing repository and PDFKit round trips…"
bash "$project_root/Scripts/audit_visual_assets.sh"
git -C "$project_root" diff --check
DEVELOPER_DIR="$xcode_developer_dir" swift "$project_root/Scripts/verify_pdf_roundtrip.swift"

echo "Testing SPDFVCore ($package_configuration)…"
DEVELOPER_DIR="$xcode_developer_dir" swift test \
    --package-path "$project_root/Core" \
    --configuration "$package_configuration"

# The CLI package references Core by local path. Cleaning prevents stale Core
# objects from surviving a package-boundary change on developer machines.
DEVELOPER_DIR="$xcode_developer_dir" swift package --package-path "$project_root/CLI" clean
echo "Testing the compiled CLI ($package_configuration)…"
DEVELOPER_DIR="$xcode_developer_dir" swift test \
    --package-path "$project_root/CLI" \
    --configuration "$package_configuration"

echo "Testing native document state transitions…"
DEVELOPER_DIR="$xcode_developer_dir" xcodebuild \
    -project "$project_root/SPDFV.xcodeproj" \
    -scheme SPDFV \
    -configuration Debug \
    -destination 'platform=macOS' \
    -parallel-testing-enabled NO \
    -only-testing:SPDFVTests \
    CODE_SIGNING_ALLOWED=NO \
    test

if [[ "${RUN_UI_TESTS:-0}" == "1" ]]; then
    echo "Running UI automation…"
    DEVELOPER_DIR="$xcode_developer_dir" xcodebuild \
        -project "$project_root/SPDFV.xcodeproj" \
        -scheme SPDFV \
        -configuration Debug \
        -destination 'platform=macOS' \
        -parallel-testing-enabled NO \
        -only-testing:SPDFVUITests \
        CODE_SIGNING_ALLOWED=NO \
        test
else
    echo "Building UI automation (set RUN_UI_TESTS=1 on an Accessibility-enabled Mac to execute it)…"
    DEVELOPER_DIR="$xcode_developer_dir" xcodebuild \
        -project "$project_root/SPDFV.xcodeproj" \
        -scheme SPDFV \
        -configuration Debug \
        -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO \
        build-for-testing
fi

echo "SPDFV validation passed (packages: $package_configuration; app tests: debug)."
