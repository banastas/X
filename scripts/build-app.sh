#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
usage='Usage: scripts/build-app.sh [debug|release]'
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) echo "$usage" >&2; exit 2;; esac
[ $# -le 1 ] || { echo "$usage" >&2; exit 2; }
# macOS 27 runs only on Apple silicon, so the app is arm64 only.
# Signing is ad hoc unless SIGN_IDENTITY names a Developer ID Application identity, as
# scripts/release.sh does; that adds the hardened runtime, a secure timestamp and
# Resources/X.entitlements, which notarization requires. release.sh also sets VERSION,
# BUILD_NUMBER, and UPDATE_FEED with UPDATE_KEY: only published builds carry an update feed.
identity="${SIGN_IDENTITY:--}"
swift build -c "$configuration" -Xswiftc -warnings-as-errors
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$PWD/dist/X.app"
# Start from an empty bundle so files removed from the project cannot linger.
rm -rf "$app_dir" .build/AppIcon.iconset
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Frameworks" .build/AppIcon.iconset
binary="$app_dir/Contents/MacOS/XDesktop"
cp "$binary_dir/XDesktop" "$binary"
# The bundle's own Frameworks folder is the only place Sparkle may load from. SwiftPM also
# records absolute paths into .build; drop them so an installed copy never loads a build's framework.
otool -l "$binary" | awk '/LC_RPATH/ { getline; getline; print $2 }' | while read -r path; do
    case "$path" in /*) [[ "$path" == /usr/lib/* ]] || install_name_tool -delete_rpath "$path" "$binary" ;; esac
done
ditto "$binary_dir/Sparkle.framework" "$app_dir/Contents/Frameworks/Sparkle.framework"

plist="$app_dir/Contents/Info.plist"
cp Resources/Info.plist "$plist"
if [ -n "${VERSION:-}" ]; then /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$plist"; fi
if [ -n "${BUILD_NUMBER:-}" ]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist"; fi
if [ -n "${UPDATE_FEED:-}" ]; then
    [ -n "${UPDATE_KEY:-}" ] || { echo 'UPDATE_FEED needs UPDATE_KEY, the public EdDSA key' >&2; exit 1; }
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $UPDATE_FEED" -c "Add :SUPublicEDKey string $UPDATE_KEY" \
        -c "Add :SUEnableAutomaticChecks bool true" -c "Add :SUScheduledCheckInterval integer 86400" "$plist"
fi

# WebsiteAdapter resolves bundled resources from Contents/Resources before the SPM fallback.
for bundle in "$binary_dir"/XDesktop_XDesktop.bundle; do
    if [ ! -d "$bundle" ]; then echo 'Missing Swift package resource bundle' >&2; exit 1; fi
    ditto "$bundle" "$app_dir/Contents/Resources/$(basename "$bundle")"
done
# About X's credits: the notice Sparkle's license asks for.
license=.build/artifacts/sparkle/Sparkle/LICENSE
[ -f "$license" ] || { echo "Missing $license; run swift package resolve" >&2; exit 1; }
{
    printf 'X for macOS is an unofficial app, independent of X Corp.\n\n'
    printf 'Updates use Sparkle (https://sparkle-project.org), under the following license.\n\n'
    cat "$license"
} > .build/Credits.txt
textutil -convert rtf -output "$app_dir/Contents/Resources/Credits.rtf" .build/Credits.txt
swift scripts/render-icon.swift Resources/x-gold-icon.png .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app_dir/Contents/Resources/AppIcon.icns"
plutil -lint "$plist"

# Sign from the inside out, Sparkle's helpers first, as Sparkle's documentation describes.
sign() {
    local flags=(--force --sign "$identity")
    if [ "$identity" != - ]; then flags+=(--options runtime --timestamp); fi
    codesign "${flags[@]}" "$@"
}
sparkle="$app_dir/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$sparkle/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
sign "$sparkle/Autoupdate"
sign "$sparkle/Updater.app"
sign "$app_dir/Contents/Frameworks/Sparkle.framework"
if [ "$identity" = - ]; then sign "$app_dir"; else sign --entitlements Resources/X.entitlements "$app_dir"; fi
codesign --verify --deep --strict "$app_dir"
echo "Built $app_dir ($(lipo -archs "$binary"))"
