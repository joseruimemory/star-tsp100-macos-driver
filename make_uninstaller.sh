#!/bin/bash
# Builds "dist/Uninstall Star TSP100 Driver.app" from the AppleScript in
# uninstaller/. The app is a window for uninstall.sh: two clicks and the usual
# macOS password prompt, instead of a Terminal command.
#
# Without any setting the app is signed ad hoc, which is fine for the Mac it
# was built on. To distribute it:
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE=<notarytool keychain profile> ./make_uninstaller.sh
set -euo pipefail
cd "$(dirname "$0")"
ID=io.github.joseruimemory.rastertostarn.uninstaller
VERSION=$(sed -n 's/^#define VERSION  *"\(.*\)".*/\1/p' rastertostarn.c)
[ -n "$VERSION" ] || { echo "no VERSION in rastertostarn.c"; exit 1; }
APP="dist/Uninstall Star TSP100 Driver.app"

mkdir -p dist
if [ -e "$APP" ]; then chmod -R u+w "$APP"; mv "$APP" "$(mktemp -d)/"; fi     # never build over an old copy
# -x: run-only. An ordinary applet may write its script back into its own
# bundle when it quits, which breaks the code signature: the next launch then
# ends in "is damaged and can't be opened".
osacompile -x -o "$APP" "uninstaller/Uninstall Star TSP100 Driver.applescript"

plist="$APP/Contents/Info.plist"
set_key() { /usr/libexec/PlistBuddy -c "Set :$1 $2" "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$plist"; }
set_key CFBundleIdentifier "$ID"
set_key CFBundleName "Uninstall Star TSP100 Driver"
set_key CFBundleShortVersionString "$VERSION"
set_key CFBundleVersion "$VERSION"
set_key LSMinimumSystemVersion "11.0"
set_key NSHumanReadableCopyright "MIT licence. Not affiliated with Star Micronics."
xattr -cr "$APP"
# Belt and braces for the same reason: nothing may rewrite the script, not
# even in a folder the user can write to (a copy unzipped in Downloads).
chmod -R a-w "$APP/Contents/Resources/Scripts"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  zip="$(mktemp -d)/uninstaller.zip"
  ditto -c -k --keepParent "$APP" "$zip"
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
fi
echo "$APP"
