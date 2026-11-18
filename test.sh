#!/bin/bash
# Tests the native driver (tsp143n.ppd and rastertostarn). Nothing is printed:
# the filters write to files.
#
# 1. Comparison with the vendor's legacy driver (tsp143.ppd and rastertostar,
#    Intel-only, run through Rosetta 2 on Apple Silicon), byte for byte, on the
#    same pages and the same options. Each driver goes the whole way with its
#    own PPD, from the PDF to the printer commands. The legacy driver is not
#    part of this repository; if it is not installed on this Mac, this part is
#    skipped and the stream of each case is only checked for being well formed.
# 2. Cancelling a long receipt while the reader is slower than the filter: the
#    filter must exit cleanly, having sent less than the whole receipt, and
#    what it sent must end by closing the page and the document.
#
# Needs ImageMagick (magick) to draw the test pages.
#
# Usage: ./test.sh [work directory]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OURS="$HERE/rastertostarn"
OUR_PPD="$HERE/tsp143n.ppd"
VENDOR=/usr/libexec/cups/filter/rastertostar
VENDOR_PPD="${VENDOR_PPD:-/Library/Printers/PPDs/Contents/Resources/tsp143.ppd.gz}"
RIP=/usr/libexec/cups/filter/cgpdftoraster
T="${1:-$(mktemp -d)}"
mkdir -p "$T" && cd "$T" || exit 1
for f in "$OURS" "$OUR_PPD" "$RIP" "$HERE/decode.py"; do
  [ -e "$f" ] || { echo "missing $f (run ./build.sh first)"; exit 2; }
done
command -v magick >/dev/null || { echo "missing ImageMagick (magick)"; exit 2; }
compare=1
if [ -x "$VENDOR" ] && [ -f "$VENDOR_PPD" ]; then
  case "$VENDOR_PPD" in *.gz) gunzip -c "$VENDOR_PPD" > vendor.ppd ;; *) cp "$VENDOR_PPD" vendor.ppd ;; esac
else
  compare=0
  echo "The vendor's legacy driver is not installed: no byte-for-byte comparison, streams are only checked."
fi
export PRINTER=test

# Test pages: a frame (no blank line anywhere), blank space at the top, in the
# middle and at the bottom, two pages, narrow paper, greys, and an empty page.
magick -size 576x320 xc:white -fill none -stroke black -strokewidth 3 -draw "rectangle 2,2 573,317" \
       -stroke none -fill black -pointsize 40 -gravity center -annotate +0+0 "TEST" \
       -units PixelsPerInch -density 203 frame.pdf
magick -size 576x240 xc:white -fill black -draw "rectangle 100,60 300,90" -draw "rectangle 350,150 500,170" \
       -units PixelsPerInch -density 203 blanks.pdf
magick \( -size 576x240 xc:white -fill black -draw "rectangle 100,60 300,90" \) \
       \( -size 576x240 xc:white -fill black -draw "rectangle 20,20 200,40" \) \
       -units PixelsPerInch -density 203 two.pdf
magick -size 406x240 xc:white -fill black -draw "rectangle 10,30 395,50" -units PixelsPerInch -density 203 narrow.pdf
magick -size 576x300 gradient:black-white -units PixelsPerInch -density 203 greys.pdf
magick -size 576x200 xc:white -units PixelsPerInch -density 203 empty.pdf

passed=0; failed=0
run() { # ppd, filter, pdf, options, copies, output prefix
  PPD="$1" CONTENT_TYPE=application/pdf FINAL_CONTENT_TYPE=printer/test "$RIP" 1 test t "$5" "$4" "$3" > "$6.ras" 2>/dev/null
  PPD="$1" CONTENT_TYPE=application/vnd.cups-raster "$2" 1 test t "$5" "$4" "$6.ras" > "$6.bin" 2> "$6.log"
}
check() { # pdf, options, copies
  local pdf="$1" op="$2" copies="${3:-1}" status
  run "$OUR_PPD" "$OURS" "$pdf" "$op" "$copies" ours; status=$?
  if [ $compare -eq 1 ]; then
    run "$T/vendor.ppd" "$VENDOR" "$pdf" "$op" "$copies" vendor
    if [ $status -eq 0 ] && cmp -s vendor.bin ours.bin; then
      passed=$((passed+1)); printf "  same     %6s bytes  %s  [%s] x%s\n" "$(wc -c < ours.bin | tr -d ' ')" "$pdf" "$op" "$copies"
    else
      failed=$((failed+1)); printf "  DIFFERS  vendor %s / ours %s bytes (exit %s)  %s  [%s] x%s\n" \
        "$(wc -c < vendor.bin | tr -d ' ')" "$(wc -c < ours.bin | tr -d ' ')" "$status" "$pdf" "$op" "$copies"
      cmp vendor.bin ours.bin | head -1
      cmp -s vendor.ras ours.ras || echo "           (the pages of the two PPDs already differ: the problem is in the PPD)"
      cp vendor.bin "differs_${failed}_vendor.bin"; cp ours.bin "differs_${failed}_ours.bin"
    fi
  elif [ $status -eq 0 ] && "$HERE/decode.py" ours.bin ours.pbm > ours.txt 2>&1; then
    passed=$((passed+1)); printf "  valid    %6s bytes  %s  [%s] x%s\n" "$(wc -c < ours.bin | tr -d ' ')" "$pdf" "$op" "$copies"
  else
    failed=$((failed+1)); printf "  INVALID  (exit %s) %s  [%s] x%s: %s\n" "$status" "$pdf" "$op" "$copies" "$(cat ours.txt 2>/dev/null)"
  fi
}

for pdf in frame.pdf blanks.pdf greys.pdf empty.pdf; do
  check $pdf "PageSize=X72MMY40MM"
done
check blanks.pdf "PageSize=X72MMY30MM"
for v in 0High 1Middle 2Low; do check blanks.pdf "PageSize=X72MMY30MM PrintSpeed=$v"; done
check blanks.pdf "PageSize=X72MMY30MM PageType=1Fixed"
check blanks.pdf "PageSize=X72MMY30MM PageCutType=1PartialCutPage DocCutType=0NoCutDoc"
check blanks.pdf "PageSize=X72MMY30MM PageCutType=0NoCutPage DocCutType=1PartialCutDoc"
for d in 0DoNotOpenDrawers 1OpenDrawer1 2OpenDrawer2 3OpenDrawer3; do check blanks.pdf "PageSize=X72MMY30MM CashDrawerSetting=$d"; done
for p in 0Millis10 1Millis100 2Millis200 5Millis500 9Millis900 12Millis1200; do check blanks.pdf "PageSize=X72MMY30MM CashDrawerSetting=1OpenDrawer1 CashDrawer1PulseWidth=$p"; done
check two.pdf "PageSize=X72MMY30MM"
check two.pdf "PageSize=X72MMY30MM PageType=1Fixed"
check two.pdf "PageSize=X72MMY30MM PageCutType=1PartialCutPage"
check two.pdf "PageSize=X72MMY30MM" 2
check narrow.pdf "PageSize=X50D8MMY30MM"
check narrow.pdf "PageSize=X50D8MMY2000MM"
check blanks.pdf "PageSize=X72MMY2000MM"
check blanks.pdf "PageSize=Custom.204x150"
check blanks.pdf "PageSize=Custom.204x1200"
check narrow.pdf "PageSize=Custom.144x100"
check narrow.pdf "PageSize=Custom.150x100"
check narrow.pdf "PageSize=Custom.180x100"
check frame.pdf "PageSize=Custom.204x113 fit-to-page"
check frame.pdf ""

# Cancelling: 4000 all-black lines (300 KB of commands), a reader that only
# starts reading after 2 s, and SIGTERM after 1 s, with the filter blocked
# writing. It must exit with 0, send less than the whole receipt, and what it
# sent must end by closing the page and the document, with no truncated line.
magick -size 576x4000 xc:black -units PixelsPerInch -density 203 black.pdf
PPD="$OUR_PPD" CONTENT_TYPE=application/pdf FINAL_CONTENT_TYPE=printer/test "$RIP" 1 test t 1 "PageSize=Custom.204x1419" black.pdf > black.ras 2>/dev/null
PPD="$OUR_PPD" "$OURS" 1 test t 1 "PageSize=Custom.204x1419" black.ras > whole.bin 2>/dev/null
rm -f pipe cancelled.bin; mkfifo pipe
( exec 3< pipe; sleep 2; cat <&3 > cancelled.bin ) &
reader=$!
PPD="$OUR_PPD" "$OURS" 1 test t 1 "PageSize=Custom.204x1419" black.ras > pipe 2> cancelled.log &
filter=$!
sleep 1; kill -TERM $filter; wait $filter; status=$?; wait $reader
whole=$(wc -c < whole.bin | tr -d ' '); sent=$(wc -c < cancelled.bin | tr -d ' ')
if [ $status -eq 0 ] && [ "$sent" -lt "$whole" ] && "$HERE/decode.py" cancelled.bin cancelled.pbm > cancelled.txt 2>&1; then
  passed=$((passed+1)); echo "  passed   cancel: exit 0, $sent of $whole bytes, stream closed ($(cut -d'|' -f1 cancelled.txt))"
else
  failed=$((failed+1)); echo "  FAILED   cancel: exit $status, $sent of $whole bytes; $(cat cancelled.txt 2>/dev/null); $(tail -1 cancelled.log)"
fi

echo "=== passed: $passed | failed: $failed | work directory: $T"
[ $failed -eq 0 ]
