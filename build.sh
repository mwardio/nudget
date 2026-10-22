#!/usr/bin/env bash

# Builds a universal (Apple silicon + Intel) Nudget.app into ./build.
#
# Optional environment:
#   CODESIGN_IDENTITY  Signing identity. Defaults to "-" (ad-hoc), which is fine
#                      for running locally. Set it to a "Developer ID
#                      Application: ..." identity for a build you intend to
#                      distribute; the release workflow does this.
#   NUDGET_VERSION     Overrides CFBundleShortVersionString, e.g. 1.2.0.
#   NUDGET_BUILD       Overrides CFBundleVersion, e.g. a CI run number.

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$project_dir/build"
app_dir="$build_dir/Nudget.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
icon_source="$project_dir/Assets/NudgetIcon.png"
iconset_dir="$build_dir/Nudget.iconset"
identity="${CODESIGN_IDENTITY:--}"
min_macos="13.0"

for tool in swiftc codesign iconutil lipo plutil sips; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Nudget requires Apple's $tool tool (install the Xcode Command Line Tools)." >&2
        exit 1
    fi
done

if [ ! -f "$icon_source" ]; then
    echo "Missing icon source: $icon_source" >&2
    exit 1
fi

# The build directory contains generated output only.
rm -rf "$build_dir"
mkdir -p "$macos_dir" "$resources_dir" "$iconset_dir"

cp "$project_dir/Info.plist" "$contents_dir/Info.plist"
cp "$icon_source" "$resources_dir/NudgetIcon.png"
if [ -n "${NUDGET_VERSION:-}" ]; then
    plutil -replace CFBundleShortVersionString -string "$NUDGET_VERSION" "$contents_dir/Info.plist"
fi
if [ -n "${NUDGET_BUILD:-}" ]; then
    plutil -replace CFBundleVersion -string "$NUDGET_BUILD" "$contents_dir/Info.plist"
fi
plutil -lint "$contents_dir/Info.plist" >/dev/null

for entry in \
    16:icon_16x16 32:icon_16x16@2x \
    32:icon_32x32 64:icon_32x32@2x \
    128:icon_128x128 256:icon_128x128@2x \
    256:icon_256x256 512:icon_256x256@2x \
    512:icon_512x512 1024:icon_512x512@2x
do
    size="${entry%%:*}"
    name="${entry#*:}"
    sips -z "$size" "$size" "$icon_source" --out "$iconset_dir/$name.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$resources_dir/Nudget.icns"
rm -rf "$iconset_dir"

compile() {
    local arch="$1"
    swiftc \
        -O \
        -warnings-as-errors \
        -target "${arch}-apple-macos${min_macos}" \
        -framework AppKit \
        -framework CoreGraphics \
        -framework ServiceManagement \
        "$project_dir/NudgetApp.swift" \
        -o "$build_dir/Nudget-$arch"
}

compile arm64
compile x86_64
lipo -create "$build_dir/Nudget-arm64" "$build_dir/Nudget-x86_64" -output "$macos_dir/Nudget"
rm -f "$build_dir/Nudget-arm64" "$build_dir/Nudget-x86_64"

# Hardened runtime is required for notarization and harmless for ad-hoc builds.
# A trusted timestamp needs the network, so skip it when signing ad-hoc.
sign_args=(--force --options runtime --sign "$identity")
if [ "$identity" = "-" ]; then
    sign_args+=(--timestamp=none)
else
    sign_args+=(--timestamp)
fi
codesign "${sign_args[@]}" "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "Built $app_dir ($(lipo -archs "$macos_dir/Nudget"))"
if [ "$identity" = "-" ]; then
    echo "Signed ad-hoc. Launch it with: open \"$app_dir\""
else
    echo "Signed as: $identity"
fi
