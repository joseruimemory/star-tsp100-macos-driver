#!/bin/bash
# Builds the installer package: dist/tsp100-macos-driver-<version>.pkg
#
# The package only owns /Library/Printers/rastertostarn; its postinstall
# script copies the PPD into the system's driver folder, so the package never
# touches the ownership or permissions of a system directory.
#
# Without any setting the package is unsigned, which is fine for the Mac it
# was built on. To distribute it, sign and notarize it:
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   INSTALLER_IDENTITY="Developer ID Installer: Name (TEAMID)" \
#   NOTARY_PROFILE=<notarytool keychain profile> ./make_pkg.sh
set -euo pipefail
cd "$(dirname "$0")"
ID=io.github.joseruimemory.rastertostarn
NAME=tsp100-macos-driver
VERSION=$(sed -n 's/^#define VERSION  *"\(.*\)".*/\1/p' rastertostarn.c)
[ -n "$VERSION" ] || { echo "no VERSION in rastertostarn.c"; exit 1; }

./build.sh
./make_ppd.py > tsp143n.ppd
cupstestppd -q tsp143n.ppd

work=$(mktemp -d)       # left for the system to clean up
root="$work/root"
install -d -m 755 "$root"
install -m 755 rastertostarn uninstall.sh "$root/"
install -m 644 tsp143n.ppd "$root/"

pkgbuild --quiet --root "$root" --identifier "$ID" --version "$VERSION" \
         --install-location /Library/Printers/rastertostarn \
         --scripts pkg/scripts --ownership recommended "$work/driver.pkg"
sed -e "s/@ID@/$ID/g" -e "s/@VERSION@/$VERSION/g" pkg/distribution.xml > "$work/distribution.xml"
mkdir -p dist
out="dist/$NAME-$VERSION.pkg"
if [ -n "${INSTALLER_IDENTITY:-}" ]; then
  productbuild --quiet --distribution "$work/distribution.xml" --package-path "$work" --resources pkg/resources \
               --sign "$INSTALLER_IDENTITY" --timestamp "$out"
else
  productbuild --quiet --distribution "$work/distribution.xml" --package-path "$work" --resources pkg/resources "$out"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$out" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$out"
fi
echo "$out"
