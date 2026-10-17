#!/usr/bin/env bash
# release.sh — builds X.app signed with Developer ID, notarizes it with Apple, staples the ticket and zips it;
# INSTALL=1 puts it in /Applications, PUBLISH=1 publishes it as an update on x.banast.as. It follows Cue's
# scripts/release.sh (Blit's by way of Rune's). X is a Swift package rather than an Xcode project, so
# scripts/build-app.sh builds and signs the app with the team's Apple Development identity (hardened runtime and
# Resources/X.entitlements), this script wraps it in an Xcode archive, and Xcode's export signs it with the team's
# Developer ID certificate: the same cloud-managed one Blit, Rune and Cue use, whose private key stays with Apple.
#
# What it needs, once (your steps: they're your account's):
#   - Xcode signed in to the team's account (Xcode › Settings › Accounts), as for the other apps, and an Apple
#     Development certificate for team F87BNUZAVJ in this Mac's Keychain (Xcode makes one when you sign in).
#   - Notary credentials in the Keychain. Blit's are the team's and work for X too, as for Rune and Cue:
#       xcrun notarytool store-credentials blit-notary --apple-id you@example.com --team-id F87BNUZAVJ
#   - For PUBLISH: the family's Sparkle key in this Mac's Keychain, Blit's (Sparkle's default account), which
#     Rune's and Cue's updates are signed with too; its public half is PUBLIC_KEY below. To publish from another
#     Mac, move it with Sparkle's generate_keys -x <file> here and -f <file> there, then delete the file.
#   - For PUBLISH: the Cloudflare Pages project that serves site/ from main as x.banast.as (site/README.md).
#
# Usage:
#   scripts/release.sh                  # test, build, notarize, staple → dist/release/
#   INSTALL=1 scripts/release.sh        # …then replace /Applications/X.app (quit X first)
#   SKIP_NOTARIZE=1 scripts/release.sh  # sign and zip only
#   VERSION=0.3.0 …                     # the version shown (CFBundleShortVersionString; Resources/Info.plist's otherwise)
#   PUBLISH=1 INSTALL=1 VERSION=0.3.0 NOTES="What changed" scripts/release.sh
#                                       # …then publish it as an update: sign the zip with Blit's key, put it in
#                                       # site/downloads/, write site/appcast.xml, commit those two and push main
#                                       # (Cloudflare Pages deploys site/ to x.banast.as)
#
# Environment: SIGN_IDENTITY (the Keychain's Apple Development identity otherwise; it must be the team's),
# NOTARY_PROFILE (default blit-notary), OUT (default dist/release), SKIP_TESTS=1 (skip swift test)
#
# Its build number is the time (YYYYMMDDHHMM), as Rune's and Cue's are: above source builds' number, so macOS
# prefers the installed copy, and rising from one release to the next, as Sparkle needs. The bundle ID stays
# as.banast.xdesktop, so the installed copy keeps the sign-in, preferences and website data of earlier builds.
# Only builds made here carry the update feed; copies built with scripts/build-app.sh never update themselves.

set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=F87BNUZAVJ
PROFILE=${NOTARY_PROFILE:-blit-notary}
OUT=${OUT:-dist/release}
SITE=https://x.banast.as
PUBLIC_KEY=/4WEfxb0faJLR2dnRoeQ2z3ym2syLxUzmOZSffgOkI4=
BUNDLE_ID=as.banast.xdesktop
TARGET=/Applications/X.app
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

# Asked first, before the build's minutes. Only ever replaces X, and never while it runs: quitting it
# could discard an unsent post (the person quits it).
if [[ "${INSTALL:-0}" == 1 ]]; then
  if [[ -e $TARGET ]] && [[ $(defaults read "$TARGET/Contents/Info" CFBundleIdentifier 2>/dev/null) != "$BUNDLE_ID" ]]; then
    echo "$TARGET is another app, not this one: move it aside first." >&2
    exit 1
  fi
  if pgrep -qf "$TARGET/Contents/MacOS/XDesktop"; then
    echo "X is running from $TARGET: quit it first (⌘Q), then run this again." >&2
    exit 1
  fi
fi
# What's published is what's committed, from main (Cloudflare Pages deploys main's site/).
if [[ "${PUBLISH:-0}" == 1 ]]; then
  [[ "${SKIP_NOTARIZE:-0}" == 1 ]] && { echo "PUBLISH needs a notarized build: leave SKIP_NOTARIZE out." >&2; exit 1; }
  [[ $(git branch --show-current) == main ]] || { echo "PUBLISH runs on main (Cloudflare Pages deploys main): switch to it first." >&2; exit 1; }
  paths=(Sources Resources Package.swift Package.resolved scripts site)
  if [[ -n $(git status --porcelain -- "${paths[@]}") ]]; then
    echo "Uncommitted changes in the app or the site: commit them first, so the release is what's in git." >&2
    git status --short -- "${paths[@]}" >&2
    exit 1
  fi
fi

IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning |
  sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)}
if [[ -z $IDENTITY ]]; then
  echo "No Apple Development certificate in the Keychain: sign in to the team in Xcode › Settings › Accounts." >&2
  exit 1
fi

echo "==> Resolving packages"
swift package resolve
if [[ "${PUBLISH:-0}" == 1 ]]; then
  # The key that signs must be the one installed copies trust.
  [[ -x "$SPARKLE_BIN/generate_keys" ]] || { echo "Sparkle's tools not found under $SPARKLE_BIN" >&2; exit 1; }
  KEY=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null) \
    || { echo "No Sparkle key in this Mac's Keychain (see the top of this script)." >&2; exit 1; }
  [[ $KEY == "$PUBLIC_KEY" ]] || { echo "The Keychain's Sparkle key isn't the one installed copies trust: stopping." >&2; exit 1; }
fi

if [[ "${SKIP_TESTS:-0}" != 1 ]]; then
  echo "==> Testing"
  swift test
fi

BUILD=$(date +%Y%m%d%H%M)
VERSION=${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)}
echo "==> Building X $VERSION ($BUILD), signed by $IDENTITY for the archive"
SIGN_IDENTITY="$IDENTITY" VERSION="$VERSION" BUILD_NUMBER="$BUILD" \
  UPDATE_FEED="$SITE/appcast.xml" UPDATE_KEY="$PUBLIC_KEY" scripts/build-app.sh release
grep -q "^TeamIdentifier=$TEAM" <<<"$(codesign -dvv dist/X.app 2>&1)" \
  || { echo "$IDENTITY isn't team $TEAM's: set SIGN_IDENTITY to the team's Apple Development identity." >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
# An Xcode archive is a folder: the app under Products/Applications and an Info.plist describing it.
ARCHIVE="$OUT/X.xcarchive"
mkdir -p "$ARCHIVE/Products/Applications"
ditto dist/X.app "$ARCHIVE/Products/Applications/X.app"
cat > "$ARCHIVE/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>ApplicationProperties</key>
  <dict>
    <key>ApplicationPath</key><string>Applications/X.app</string>
    <key>Architectures</key><array>$(for arch in $(lipo -archs dist/X.app/Contents/MacOS/XDesktop); do printf '<string>%s</string>' "$arch"; done)</array>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>SigningIdentity</key><string>$IDENTITY</string>
    <key>Team</key><string>$TEAM</string>
  </dict>
  <key>ArchiveVersion</key><integer>2</integer>
  <key>CreationDate</key><date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
  <key>Name</key><string>X</string>
  <key>SchemeName</key><string>XDesktop</string>
</dict>
</plist>
PLIST
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT" -allowProvisioningUpdates -quiet
APP="$OUT/X.app"
codesign --verify --deep --strict "$APP"
SIGNED=$(codesign -dvv "$APP" 2>&1)   # -vv: the authorities (-v shows none)
grep -E "^Authority=Developer ID|^TeamIdentifier|runtime" <<<"$SIGNED" || true
grep -q "^Authority=Developer ID Application" <<<"$SIGNED" || { echo "Not signed with Developer ID: stopping." >&2; exit 1; }
grep -q "^TeamIdentifier=$TEAM" <<<"$SIGNED" || { echo "Not signed by team $TEAM: stopping." >&2; exit 1; }
# Notarization needs the hardened runtime; the website's camera and microphone need the entitlements.
grep -q "flags=.*runtime" <<<"$SIGNED" || { echo "The export dropped the hardened runtime: stopping." >&2; exit 1; }
ENTITLEMENTS=$(codesign -d --entitlements - "$APP" 2>/dev/null)
for key in com.apple.security.device.camera com.apple.security.device.audio-input; do
  grep -q "$key" <<<"$ENTITLEMENTS" || { echo "The export dropped $key: stopping." >&2; exit 1; }
done
[[ $(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$APP/Contents/Info.plist") == "$SITE/appcast.xml" ]] \
  || { echo "The app's SUFeedURL isn't $SITE/appcast.xml: stopping." >&2; exit 1; }

if [[ "${SKIP_NOTARIZE:-0}" != 1 ]]; then
  echo "==> Notarizing (this usually takes a few minutes)"
  ditto -c -k --keepParent "$APP" "$OUT/X-notarize.zip"
  xcrun notarytool submit "$OUT/X-notarize.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$OUT/X-notarize.zip"
  spctl --assess --type execute -vv "$APP"
fi

ZIP="$OUT/X-$VERSION-$BUILD.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> $ZIP"

if [[ "${PUBLISH:-0}" == 1 ]]; then
  echo "==> Publishing $VERSION ($BUILD) as an update"
  # Cloudflare Pages serves files up to 25 MiB.
  (( $(stat -f %z "$ZIP") < 25 * 1024 * 1024 )) || { echo "$ZIP is over Cloudflare Pages' 25 MiB: stopping." >&2; exit 1; }
  # The EdDSA signature and length, signed with the key in this Mac's Keychain (Blit's).
  SIGNATURE=$("$SPARKLE_BIN/sign_update" "$ZIP")
  MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")
  NAME="X-$VERSION-$BUILD.zip"   # a name of its own: one served from a cache under an old name wouldn't match its signature
  mkdir -p site/downloads
  rm -f site/downloads/X-*.zip          # the site keeps the current release only
  cp "$ZIP" "site/downloads/$NAME"
  cp "$ZIP" site/downloads/X.zip        # a stable name for the page's Download link
  NOTES_HTML=$(printf '%s' "${NOTES:-Fixes and improvements.}" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
  cat > site/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>X for macOS</title>
    <link>$SITE/appcast.xml</link>
    <description>Updates for X for macOS</description>
    <language>en</language>
    <item>
      <title>X for macOS $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>$NOTES_HTML</p>]]></description>
      <enclosure url="$SITE/downloads/$NAME" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML
  git add site/downloads site/appcast.xml
  git commit -q -m "Publish X $VERSION ($BUILD)" -- site/downloads site/appcast.xml
  git push -q
  echo "==> Published: $SITE/downloads/$NAME (Cloudflare Pages deploys it in about a minute)"
fi

if [[ "${INSTALL:-0}" == 1 ]]; then
  echo "==> Installing $TARGET"
  rm -rf "$TARGET.new"
  ditto "$APP" "$TARGET.new"
  rm -rf "$TARGET"
  mv "$TARGET.new" "$TARGET"
  "$LSREGISTER" -f "$TARGET"
  echo "Installed $TARGET: X $VERSION ($BUILD), from $(git rev-parse --short HEAD)$(git diff --quiet HEAD -- Sources Resources Package.swift || echo ', with changes not committed'). Open it from /Applications."
fi

# Only the installed copy should be the one macOS opens: not the build's or the release folder's.
for copy in "$APP" dist/X.app; do
  [[ -d "$copy" ]] && { "$LSREGISTER" -u "$PWD/$copy" >/dev/null 2>&1 || true; }
done
