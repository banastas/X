#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) echo 'Usage: scripts/build-app.sh [debug|release]' >&2; exit 2;; esac
swift build -c "$configuration" -Xswiftc -warnings-as-errors
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$PWD/dist/X.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" .build/AppIcon.iconset
cp "$binary_dir/XDesktop" "$app_dir/Contents/MacOS/XDesktop"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
# WebsiteAdapter resolves bundled resources from Contents/Resources before the SPM fallback.
for bundle in "$binary_dir"/XDesktop_XDesktop.bundle; do
    if [ ! -d "$bundle" ]; then echo 'Missing Swift package resource bundle' >&2; exit 1; fi
    ditto "$bundle" "$app_dir/Contents/Resources/$(basename "$bundle")"
done
swift scripts/render-icon.swift Resources/x-gold-icon.png .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app_dir/Contents/Resources/AppIcon.icns"
plutil -lint "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
echo "Built $app_dir"
