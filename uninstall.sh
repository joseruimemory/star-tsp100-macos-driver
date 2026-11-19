#!/bin/bash
# Removes the driver. For most people: open "Uninstall Star TSP100 Driver" in
# Applications > Utilities; it runs this script after the usual macOS password
# prompt. From Terminal:
#
#   sudo /Library/Printers/rastertostarn/uninstall.sh
#
# Print queues that use the driver are removed too, because they cannot print
# without it.
#   --keep-queues   leave those print queues alone
#   --list-queues   print the printers that use the driver, and exit
#   --dry-run       say what would be removed, remove nothing (needs no sudo)
#
# The whole script is one function, read to the end before it runs, because it
# deletes itself.
main() {
  export LC_ALL=C LANG=C PATH=/usr/bin:/bin:/usr/sbin:/sbin
  local home=/Library/Printers/rastertostarn
  local filter=$home/rastertostarn
  local driver=/Library/Printers/PPDs/Contents/Resources/tsp143n.ppd.gz
  local app="/Applications/Utilities/Uninstall Star TSP100 Driver.app"
  local keep=0 dry=0 list=0 arg ppd queue name queues=""
  for arg in "$@"; do
    case "$arg" in
      --keep-queues) keep=1 ;;
      --dry-run) dry=1 ;;
      --list-queues) list=1 ;;
      *) echo "Unknown option: $arg"; exit 64 ;;
    esac
  done

  # Queue names never contain spaces, so a plain list is enough.
  for ppd in /etc/cups/ppd/*.ppd; do
    [ -f "$ppd" ] || continue
    grep -q "^\*cupsFilter:.*$filter\"" "$ppd" 2>/dev/null || continue
    queues="$queues $(basename "$ppd" .ppd)"
  done

  if [ "$list" -eq 1 ]; then
    for queue in $queues; do
      name=$(lpoptions -p "$queue" 2>/dev/null | sed -n "s/.*printer-info='\([^']*\)'.*/\1/p")
      [ -n "$name" ] || name=$(lpoptions -p "$queue" 2>/dev/null | tr ' ' '\n' | sed -n 's/^printer-info=//p' | head -1)
      echo "${name:-$queue}"
    done
    exit 0
  fi

  if [ "$dry" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo $0"; exit 1
  fi

  for queue in $queues; do
    if [ "$keep" -eq 1 ]; then
      echo "Print queue $queue still points at the removed driver."
    elif [ "$dry" -eq 1 ]; then
      echo "Would remove print queue $queue."
    elif lpadmin -x "$queue"; then
      echo "Removed print queue $queue."
    else
      echo "Could not remove print queue $queue."
    fi
  done

  if [ "$dry" -eq 1 ]; then
    for arg in "$driver" "$app" "$home"; do
      [ -e "$arg" ] && echo "Would remove $arg"
    done
    echo "Nothing was removed (dry run)."
    exit 0
  fi

  rm -f "$driver"
  rm -rf "$app"
  rm -rf "$home"
  pkgutil --forget io.github.joseruimemory.rastertostarn >/dev/null 2>&1
  echo "The Star TSP100 driver has been removed."
}
main "$@"
