#!/bin/bash
# Installs a locally built driver without the installer package:
#   ./build.sh && sudo ./install.sh
# Same result as the package: the filter, the PPD and the uninstaller go to
# /Library/Printers/rastertostarn, a copy of the PPD goes to the folder where
# macOS looks for printer drivers, and the print queues of the printer are
# switched to the driver.
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo $0"; exit 1; }
[ -x rastertostarn ] || { echo "Build first: ./build.sh"; exit 1; }
cupstestppd -q tsp143n.ppd || { echo "tsp143n.ppd does not pass cupstestppd"; exit 1; }
install -d -o root -g wheel -m 755 /Library/Printers/rastertostarn
install -o root -g wheel -m 755 rastertostarn uninstall.sh /Library/Printers/rastertostarn/
install -o root -g wheel -m 644 tsp143n.ppd /Library/Printers/rastertostarn/
# The uninstaller app, when it has been built (./make_uninstaller.sh).
if [ -d "dist/Uninstall Star TSP100 Driver.app" ]; then
  rm -rf "/Library/Printers/rastertostarn/Uninstall Star TSP100 Driver.app"
  ditto "dist/Uninstall Star TSP100 Driver.app" "/Library/Printers/rastertostarn/Uninstall Star TSP100 Driver.app"
  chown -R root:wheel "/Library/Printers/rastertostarn/Uninstall Star TSP100 Driver.app"
fi
pkg/scripts/postinstall
echo "Installed rastertostarn $(sed -n 's/^#define VERSION  *"\(.*\)".*/\1/p' rastertostarn.c)."
