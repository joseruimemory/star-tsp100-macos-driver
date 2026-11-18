# tsp100-macos-driver

A native macOS driver for the **Star TSP143** receipt printer (the original
TSP100 "futurePRNT" series, released in 2005). It runs on Apple Silicon and
Intel Macs without Rosetta.

It is a regular CUPS driver: one small filter, `rastertostarn`, and a PPD.
Once installed, the printer works from the print dialog and from `lp`, like
any other printer.

## Why

On current Macs, the driver that covers the original TSP100 is Star's legacy
CUPS driver, whose filters are Intel-only binaries: on Apple Silicon they run
only through Rosetta 2. Star's current macOS driver lists the TSP100IIU and
later models, not the original series (as of November 2026).

This driver does the same job with a universal binary that needs nothing but
the CUPS library that ships with macOS.

## Status

- Printer: TSP143 with cutter, over USB (`0519:0003`, IEEE 1284 ID
  `MFG:Star;CMD:STAR;MDL:TSP143 (STR_T-001)`).
- Tested on macOS 26 on Apple Silicon, printing real receipts. The Intel half
  of the binary gives the same output when run through Rosetta; it has not
  been tried on an Intel Mac. Built for macOS 11 or later.
- The output is byte-for-byte identical to the legacy driver's in 35 test
  cases (see [How it was tested](#how-it-was-tested)).

## Install

Download the installer package from the [Releases](../../releases) page and
open it. It installs:

- the filter, the PPD and an uninstaller in `/Library/Printers/rastertostarn`
- a copy of the PPD in `/Library/Printers/PPDs/Contents/Resources`, where
  macOS looks for printer drivers

If the printer is already set up on the Mac, its print queue is switched to
this driver. If it is plugged in and not set up yet, a queue named
`Star_TSP143` is created. Otherwise, plug the printer in and add it in
System Settings > Printers & Scanners; if macOS does not pick the driver by
itself, choose "Star TSP143 native" under Use > Select Software.

### From source

Needs the Xcode command line tools.

    ./build.sh
    sudo ./install.sh

### Uninstall

    sudo /Library/Printers/rastertostarn/uninstall.sh

This also removes the print queues that use the driver; add `--keep-queues`
to leave them.

## Printing

Receipts are 72 mm wide (576 dots at 203 dpi) and as long as their content:
the driver does not send the blank lines at the end of a page, and it cuts at
the end of the document.

    lp -d Star_TSP143 -o PageSize=Custom.204x400 receipt.pdf

| Option | Values (default first) | What it does |
| --- | --- | --- |
| `PageSize` | `X72MMY200MM`, other `X72MMY...MM` and `X50D8MMY...MM` sizes, `Custom.WIDTHxLENGTH` | 72 mm or 50.8 mm paper, in lengths from 30 mm to 2 m; custom sizes are in points, up to 204 x 5670 |
| `DocCutType` | `1PartialCutDoc`, `0NoCutDoc` | cut at the end of the document |
| `PageCutType` | `0NoCutPage`, `1PartialCutPage` | cut after every page |
| `PageType` | `0Variable`, `1Fixed` | variable length (blank lines at the end are dropped) or the full page length |
| `PrintSpeed` | `0High`, `1Middle`, `2Low` | print speed |
| `CashDrawerSetting` | `0DoNotOpenDrawers`, `1OpenDrawer1`, `2OpenDrawer2`, `3OpenDrawer3` | open the cash drawer wired to the printer: none, drawer 1, drawer 2, or both |
| `CashDrawer1PulseWidth` | `2Millis200`, `0Millis10`, `1Millis100` to `12Millis1200` | length of the pulse that opens drawer 1 |

The option and page size names are the same as in Star's driver, on purpose:
print settings and commands written for it keep working.

## How it was made

No vendor source code was read. The command sequence was worked out by running
the legacy filter by hand on test pages, with its output captured to a file
instead of sent to a printer, and reading the result. It is written down at
the top of [`rastertostarn.c`](rastertostarn.c). The PPD is written from
scratch by [`make_ppd.py`](make_ppd.py).

## How it was tested

`./test.sh` prints nothing: the filters write to files. It needs ImageMagick
to draw the test pages.

- **Against the legacy driver.** If Star's legacy driver is installed on the
  Mac, each driver takes the same PDF through its own PPD and filter, and the
  two command streams must be identical. There are 35 cases: print speeds,
  cuts, cash drawer, two pages, copies, narrow paper, custom sizes, greys and
  an empty page. The legacy driver is not part of this repository; without
  it, each stream is only checked for being well formed.
- **Cancelling.** A long receipt is cancelled while the filter is blocked
  writing. The filter must exit cleanly, and what it sent must still close
  the page and the document, so the printer is not left waiting in the middle
  of a line.

`./decode.py stream.bin out.pbm` draws what a command stream would print.

## Limitations

- Only the TSP143 has been tested. Other models of the original series use
  the same raster mode and may work with a PPD of their own, but none has
  been tried.
- USB only.
- Pages reach the filter as 1-bit raster from the macOS PDF rasterizer, so
  greys and soft edges come out dithered.
- The printer reports no serial number over USB, so macOS ties the print
  queue to the USB port. In another port it shows up as a new printer.
- macOS warns that printer drivers of this kind (a PPD and a filter) "are
  deprecated and will stop working in a future version of CUPS". That applies
  to every classic driver, the vendor's included. They work on macOS 26.

## Related work

- [at-point-of-sale/StarGraphicsPrinterEncoder](https://github.com/at-point-of-sale/StarGraphicsPrinterEncoder)
  (MIT): a library that produces the same raster commands, from Star's
  published command specification.
- [dalpil/tsp100-print](https://github.com/dalpil/tsp100-print) (MIT): sends
  raster images to LAN-connected TSP100 and TSP143 printers.
- [drobban/starcupsdrv](https://github.com/drobban/starcupsdrv): Star's own
  CUPS driver source for Linux, with a patch for the TSP800II.
- [mike-marcacci/rastertotspl](https://github.com/mike-marcacci/rastertotspl)
  (Apache-2.0): a CUPS driver for TSPL label printers on Apple Silicon, in
  the same spirit.

## Licence

[MIT](LICENSE).

Star, TSP100 and futurePRNT are trademarks of Star Micronics Co., Ltd. This
project is not affiliated with, or endorsed by, Star Micronics.
