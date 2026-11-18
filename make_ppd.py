#!/usr/bin/python3
"""make_ppd.py - writes the PPD of the native Star TSP143 driver.

The PPD is the file that describes the printer to macOS: paper sizes, options
and the filter that translates the page. This one is written from scratch. The
page size and option names are the same as in the vendor's driver, so existing
print settings and commands keep working, and so test.sh can run both drivers
with the same options. The filter is ours all the way.

Usage: make_ppd.py > tsp143n.ppd
"""
FILTER = "/Library/Printers/rastertostarn/rastertostarn"
WIDTHS = (("X72MM", "72mm", 204), ("X50D8MM", "50.8mm", 144))
LENGTHS = list(range(30, 201, 10)) + [2000]          # in mm
DEFAULT = "X72MMY200MM"


def points(mm):
    # The lengths of the vendor's driver, to the point (2000 mm gives 5668):
    # the same names have to give the same pages.
    return int(mm * 2.834)


def sizes():
    for prefix, text, width in WIDTHS:
        for mm in LENGTHS:
            yield f"{prefix}Y{mm}MM", f"{text} * {mm}mm", width, points(mm)


def option(name, title, default, choices):
    lines = [f"*OpenUI *{name}/{title}: PickOne", f"*OrderDependency: 20 AnySetup *{name}", f"*Default{name}: {default}"]
    lines += [f'*{name} {key}/{text}: ""' for key, text in choices]
    lines.append(f"*CloseUI: *{name}")
    return lines


def main():
    s = ['*PPD-Adobe: "4.3"',
         "*% Star TSP100 series (TSP143, TSP113), raster mode: native CUPS filter rastertostarn.",
         "*% Written from scratch. Option and page size names match Star's own driver,",
         "*% so existing print settings and commands keep working.",
         '*FormatVersion: "4.3"', '*FileVersion: "1.0"', "*LanguageVersion: English", "*LanguageEncoding: ISOLatin1",
         '*PCFileName: "TSP143N.PPD"', '*Manufacturer: "Star"', '*Product: "(TSP143)"',
         '*1284DeviceID: "MFG:Star;CMD:STAR;MDL:TSP143 (STR_T-001);CLS:PRINTER;"',
         "*cupsVersion: 1.4", "*cupsManualCopies: True", "*cupsModelNumber: 143",
         f'*cupsFilter: "application/vnd.cups-raster 0 {FILTER}"',
         '*ModelName: "Star TSP143 native"', '*ShortNickName: "Star TSP143 native"',
         '*NickName: "Star TSP143 native raster driver (rastertostarn)"',
         '*PSVersion: "(3010.000) 0"', '*LanguageLevel: "3"', "*ColorDevice: False", "*DefaultColorSpace: Gray",
         "*FileSystem: False", '*Throughput: "1"', "*LandscapeOrientation: Plus90", "*VariablePaperSize: True",
         "*TTRasterizer: Type42", "*cupsSNMPSupplies: False", ""]
    code = '"<</PageSize[{} {}]/HWResolution[203 203]/ImagingBBox null>>setpagedevice"'
    for key in ("PageSize", "PageRegion"):
        s += [f"*OpenUI *{key}/Media Size: PickOne", f"*OrderDependency: 10 AnySetup *{key}", f"*Default{key}: {DEFAULT}"]
        s += [f"*{key} {n}/{t}: {code.format(w, h)}" for n, t, w, h in sizes()]
        s += [f"*CloseUI: *{key}", ""]
    s.append(f"*DefaultImageableArea: {DEFAULT}")
    s += [f'*ImageableArea {n}/{t}: "0.0 0.0 {w}.0 {h}.0"' for n, t, w, h in sizes()]
    s += ["", f"*DefaultPaperDimension: {DEFAULT}"]
    s += [f'*PaperDimension {n}/{t}: "{w} {h}"' for n, t, w, h in sizes()]
    s += ["", '*MaxMediaWidth: "204"', '*MaxMediaHeight: "5670"', "*HWMargins: 0 0 0 0",
          '*CustomPageSize True: "pop pop pop <</PageSize[5 -2 roll]/HWResolution[203 203]/ImagingBBox null>>setpagedevice"',
          "*ParamCustomPageSize Width: 1 points 72 204", "*ParamCustomPageSize Height: 2 points 72 5670",
          "*ParamCustomPageSize WidthOffset: 3 points 0 0", "*ParamCustomPageSize HeightOffset: 4 points 0 0",
          "*ParamCustomPageSize Orientation: 5 int 0 0", ""]
    s.append("*OpenGroup: OutputGroup/Output Options")
    s += option("PrintSpeed", "Print Speed", "0High", [("0High", "High"), ("1Middle", "Middle"), ("2Low", "Low")])
    s += option("PageType", "Page Type", "0Variable", [("0Variable", "Variable Length"), ("1Fixed", "Fixed Length")])
    s += ["*CloseGroup: OutputGroup", "", "*OpenGroup: CutGroup/Cut Options"]
    s += option("PageCutType", "Page Cut Type", "0NoCutPage", [("0NoCutPage", "No Cut"), ("1PartialCutPage", "Partial Cut")])
    s += option("DocCutType", "Document Cut Type", "1PartialCutDoc", [("0NoCutDoc", "No Cut"), ("1PartialCutDoc", "Partial Cut")])
    s += ["*CloseGroup: CutGroup", "", "*OpenGroup: CashDrawerGroup/Cash Drawer Control"]
    s += option("CashDrawerSetting", "Cash Drawer", "0DoNotOpenDrawers",
                [("0DoNotOpenDrawers", "Do Not Open Drawers"), ("1OpenDrawer1", "Open Cash Drawer 1"),
                 ("2OpenDrawer2", "Open Cash Drawer 2"), ("3OpenDrawer3", "Open Cash Drawers 1 and 2")])
    s += option("CashDrawer1PulseWidth", "Cash Drawer 1 Pulse Width", "2Millis200",
                [("0Millis10", "10 milliseconds")] + [(f"{k}Millis{k * 100}", f"{k * 100} milliseconds") for k in range(1, 13)])
    s += ["*CloseGroup: CashDrawerGroup", "", '*DefaultFont: Courier', '*Font Courier: Standard "(1.05)" Standard ROM', "", "*% End of file"]
    print("\n".join(s))


if __name__ == "__main__":
    main()
