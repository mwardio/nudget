#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$project_dir/build"
app_dir="$build_dir/Nudget.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
icon_source="$project_dir/Assets/NudgetIcon.png"
iconset_dir="$build_dir/Nudget.iconset"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "Nudget requires Apple's Swift compiler (Xcode Command Line Tools)." >&2
    exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
    echo "Nudget requires Apple's codesign tool." >&2
    exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
    echo "Nudget requires Apple's iconutil tool." >&2
    exit 1
fi

if [ ! -f "$icon_source" ]; then
    echo "Missing icon source: $icon_source" >&2
    exit 1
fi

# The build directory contains generated output only.
rm -rf "$build_dir"
mkdir -p "$macos_dir" "$resources_dir" "$iconset_dir"

cp "$project_dir/Info.plist" "$contents_dir/Info.plist"
cp "$icon_source" "$resources_dir/NudgetIcon.png"
plutil -lint "$contents_dir/Info.plist" >/dev/null

sips -z 16 16 "$icon_source" --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$icon_source" --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 "$icon_source" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$icon_source" --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$icon_source" --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$icon_source" --out "$iconset_dir/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$icon_source" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset_dir" -o "$resources_dir/Nudget.icns"
rm -rf "$iconset_dir"

architecture="$(uname -m)"
swiftc \
    -O \
    -warnings-as-errors \
    -target "${architecture}-apple-macos13.0" \
    -framework AppKit \
    -framework CoreGraphics \
    -framework ServiceManagement \
    "$project_dir/NudgetApp.swift" \
    -o "$macos_dir/Nudget"

codesign --force --sign - --timestamp=none "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "Built $app_dir"
echo "Launch it with: open \"$app_dir\""
