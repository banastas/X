#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
usage='Usage: scripts/build-app.sh [debug|release] [universal]'
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) echo "$usage" >&2; exit 2;; esac
# Builds target this Mac. "universal" adds an Intel slice for copying the app to another Mac;
# recent Xcode releases warn that x86_64 is deprecated, but the slice still targets macOS 14.
arch_flags=()
case "${2:-}" in
    "") ;;
    universal) arch_flags=(--arch arm64 --arch x86_64) ;;
    *) echo "$usage" >&2; exit 2 ;;
esac
swift build -c "$configuration" ${arch_flags[@]+"${arch_flags[@]}"} -Xswiftc -warnings-as-errors
binary_dir="$(swift build -c "$configuration" ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)"
app_dir="$PWD/dist/X.app"
# Start from an empty bundle so files removed from the project cannot linger.
rm -rf "$app_dir" .build/AppIcon.iconset
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
echo "Built $app_dir ($(lipo -archs "$app_dir/Contents/MacOS/XDesktop"))"
