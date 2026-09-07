#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root="$project_root/SPDFV"
icon_root="$source_root/Assets.xcassets/SPDFVIcons"

if command -v rg >/dev/null 2>&1; then
    symbol_matches() {
        rg -n 'Image\(systemName:|NSImage\(systemSymbolName:|UIImage\(systemName:|systemImage:' "$source_root" --glob '*.swift'
    }
    emoji_matches() {
        rg -n --pcre2 '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}]' "$project_root" \
            --glob '!**/*.xcodeproj/**' \
            --glob '!**/*.png' \
            --glob '!**/*.svg'
    }
else
    symbol_matches() {
        git -C "$project_root" grep -n -E \
            'Image\(systemName:|NSImage\(systemSymbolName:|UIImage\(systemName:|systemImage:' \
            -- ':(glob)SPDFV/**/*.swift'
    }
    emoji_matches() {
        git -C "$project_root" grep -n -P '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}]' \
            -- . \
            ':(exclude,glob)**/*.xcodeproj/**' \
            ':(exclude,glob)**/*.png' \
            ':(exclude,glob)**/*.svg'
    }
fi

if symbol_matches; then
    echo "Visual audit failed: platform symbol API usage remains."
    exit 1
fi

if emoji_matches; then
    echo "Visual audit failed: emoji code points remain in project text."
    exit 1
fi

icon_count="$(find "$icon_root" -name '*.svg' -type f | wc -l | tr -d ' ')"
if [[ "$icon_count" != "79" ]]; then
    echo "Visual audit failed: expected 79 custom SVGs, found $icon_count."
    exit 1
fi

declared_icons="$(
    awk '
        /enum SPDFVIconName/ { reading = 1; next }
        reading && /var assetName/ { exit }
        reading && /^[[:space:]]*case / {
            sub(/^[[:space:]]*case /, "")
            gsub(/,/, " ")
            for (i = 1; i <= NF; i++) print $i
        }
    ' "$source_root/SPDFVTheme.swift" | sort
)"
asset_icons="$(
    find "$icon_root" -name 'SPDFVIcon-*.imageset' -type d -maxdepth 1 \
        | sed -E 's|.*/SPDFVIcon-||; s|\.imageset$||' \
        | sort
)"
if [[ "$declared_icons" != "$asset_icons" ]]; then
    echo "Visual audit failed: the Swift icon vocabulary and SVG assets differ."
    diff <(printf '%s\n' "$declared_icons") <(printf '%s\n' "$asset_icons") || true
    exit 1
fi

echo "Visual audit passed: 79 custom SVGs, no emoji, no platform symbol APIs."
