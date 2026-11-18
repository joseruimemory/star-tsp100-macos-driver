#!/bin/bash
# Removes the driver:  sudo /Library/Printers/rastertostarn/uninstall.sh
# Print queues that use it are removed too, because they cannot print without
# it; pass --keep-queues to leave them alone.
main() {
  export LC_ALL=C LANG=C PATH=/usr/bin:/bin:/usr/sbin:/sbin
  [ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo $0"; exit 1; }
  local filter=/Library/Printers/rastertostarn/rastertostarn ppd queue
  for ppd in /etc/cups/ppd/*.ppd; do
    [ -f "$ppd" ] || continue
    grep -q "^\*cupsFilter:.*$filter\"" "$ppd" || continue
    queue=$(basename "$ppd" .ppd)
    if [ "${1:-}" = "--keep-queues" ]; then
      echo "Print queue $queue still points at the removed driver."
    elif lpadmin -x "$queue"; then
      echo "Removed print queue $queue."
    fi
  done
  rm -f /Library/Printers/PPDs/Contents/Resources/tsp143n.ppd.gz
  rm -rf /Library/Printers/rastertostarn
  pkgutil --forget io.github.joseruimemory.rastertostarn >/dev/null 2>&1
  echo "The Star TSP143 native driver has been removed."
}
main "$@"
