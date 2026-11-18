#!/bin/bash
# Builds rastertostarn as a universal binary (arm64 and x86_64) next to the
# source. Needs only the Xcode command line tools; the one library is the
# system's libcups (Apple marks its PPD functions as deprecated, hence the
# silenced warning).
#
# Signing: ad hoc by default, which is all a locally built copy needs. Set
# CODESIGN_IDENTITY to a "Developer ID Application: ..." identity to sign for
# distribution, with the hardened runtime and a secure timestamp, as
# notarization requires.
set -euo pipefail
cd "$(dirname "$0")"
ID=io.github.joseruimemory.rastertostarn
xcrun clang -O2 -Wall -Wextra -Wno-deprecated-declarations \
    -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
    -o rastertostarn rastertostarn.c -lcups
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --identifier "$ID" --sign "$CODESIGN_IDENTITY" rastertostarn
else
  codesign --force --identifier "$ID" --sign - rastertostarn
fi
file rastertostarn
