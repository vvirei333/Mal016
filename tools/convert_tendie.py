#!/usr/bin/env python3
"""convert_tendie.py — convert an iOS 17 "ParameterizedCA" tendies wallpaper
into the iOS 16 "LayeredAnimation" layout (Background/Foreground/Floating .ca).

usage: convert_tendie.py <src .wallpaper dir> <out .wallpaper dir> [identifier name]

The iOS 17 pack has ONE `<something>.ca` whose main.caml root contains named
groups BACKGROUND / FLOATING (optionally FOREGROUND) in a 393x852 canvas.
iOS 16's WallpaperKit wants three separate .ca packages, each with the rich
index.xml (documentWidth/Height + publishedObjectNames) and a 414x736 root.

NOTE: experimental — validated visually, may need tweaks per pack.
"""
import os, sys, shutil, plistlib, copy, re
import xml.etree.ElementTree as ET

NS = "http://www.apple.com/CoreAnimation/1.0"
ET.register_namespace("", NS)

NATIVE_INDEX = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>assetManifest</key>
	<string>assetManifest.caml</string>
	<key>documentHeight</key>
	<real>736</real>
	<key>documentResizesToView</key>
	<false/>
	<key>documentWidth</key>
	<real>414</real>
	<key>dynamicGuidesEnabled</key>
	<true/>
	<key>geometryFlipped</key>
	<false/>
	<key>guidesEnabled</key>
	<true/>
	<key>interactiveMouseEventsEnabled</key>
	<true/>
	<key>interactiveShowsCursor</key>
	<true/>
	<key>interactiveTouchEventsEnabled</key>
	<false/>
	<key>loopEnd</key>
	<real>+infinity</real>
	<key>loopStart</key>
	<real>0.0</real>
	<key>loopingEnabled</key>
	<true/>
	<key>multitouchDisablesMouse</key>
	<false/>
	<key>multitouchEnabled</key>
	<false/>
	<key>plugins</key>
	<array/>
	<key>presentationMouseEventsEnabled</key>
	<true/>
	<key>presentationShowsCursor</key>
	<true/>
	<key>presentationTouchEventsEnabled</key>
	<false/>
	<key>publishedObjectNames</key>
	<array>
		<string>{PUBLISHED}</string>
	</array>
	<key>rootDocument</key>
	<string>main.caml</string>
	<key>savesWindowFrame</key>
	<false/>
	<key>scalesToFitInPlayer</key>
	<true/>
	<key>showsTouches</key>
	<true/>
	<key>snappingEnabled</key>
	<true/>
	<key>timelineMarkers</key>
	<string>[(null)]</string>
	<key>touchesColor</key>
	<string>1 1 0 0.8</string>
	<key>unitsInPixelsInPlayer</key>
	<false/>
</dict>
</plist>
"""

ASSET_MANIFEST = """<?xml version="1.0" encoding="UTF-8"?>

<caml xmlns="http://www.apple.com/CoreAnimation/1.0">
  <MicaAssetManifest>
    <modules type="NSArray"/>
  </MicaAssetManifest>
</caml>
"""

def q(name): return "{%s}%s" % (NS, name)

def find_ca(wp_dir):
    for d in os.listdir(wp_dir):
        p = os.path.join(wp_dir, d)
        if d.endswith(".ca") and os.path.isdir(p) and os.path.exists(os.path.join(p, "main.caml")):
            return p
    return None

def parse_root(ca_dir):
    tree = ET.parse(os.path.join(ca_dir, "main.caml"))
    caml = tree.getroot()
    root = next((c for c in caml if c.tag == q("CALayer")), None)
    if root is None:
        raise RuntimeError("no CALayer root")
    groups = {}
    subs = next((c for c in root if c.tag == q("sublayers")), None)
    if subs is not None:
        for g in list(subs):
            gid = (g.get("id") or g.get("name") or "").upper()
            groups[gid] = g
    return caml, root, groups

def build_layer_doc(pack_caml, pack_root, group_elem, published, src_w, src_h, dst_w=414, dst_h=736):
    scale = dst_w / float(src_w)
    # fresh caml doc
    caml = ET.Element(q("caml"))
    root = ET.SubElement(caml, q("CALayer"), {
        "allowsEdgeAntialiasing": "1", "allowsGroupOpacity": "1",
        "bounds": "0 0 %g %g" % (dst_w, dst_h),
        "contentsFormat": "RGBA8",
        "geometryFlipped": "1", "hidden": "0",
        "name": "Root Layer", "position": "%g %g" % (dst_w/2, dst_h/2),
    })
    subs = ET.SubElement(root, q("sublayers"))
    outer = ET.SubElement(subs, q("CALayer"), {
        "id": published, "name": published,
        "anchorPoint": "0 0", "bounds": "0 0 %g %g" % (dst_w, dst_h),
        "contentsFormat": "RGBA8", "geometryFlipped": "0", "hidden": "0",
        "position": "0 0",
    })
    outer_subs = ET.SubElement(outer, q("sublayers"))
    # design canvas mirroring the pack's original root geometry
    canvas = ET.SubElement(outer_subs, q("CALayer"), {
        "name": "Design Canvas",
        "bounds": "0 0 %g %g" % (src_w, src_h),
        "position": "%g %g" % (dst_w/2, dst_h/2),
        "geometryFlipped": pack_root.get("geometryFlipped", "0"),
        "transform": "scale(%.6f, %.6f, 1)" % (scale, scale),
        "allowsEdgeAntialiasing": "1", "allowsGroupOpacity": "1",
        "contentsFormat": "RGBA8",
    })
    canvas_subs = ET.SubElement(canvas, q("sublayers"))
    if group_elem is not None:
        g = copy.deepcopy(group_elem)
        # keep the pack's original layer id inside; the published object is the
        # outer wrapper whose id == published name
        canvas_subs.append(g)
    # state machine: copy from the pack if present (3 states / 6 transitions)
    for tag in ("states", "stateTransitions"):
        src = next((c for c in pack_root if c.tag == q(tag)), None)
        if src is not None:
            root.append(copy.deepcopy(src))
    return caml

def convert(src_wp, out_wp, ident=None, name=None):
    src_ca = find_ca(src_wp)
    if not src_ca:
        raise RuntimeError("no .ca package in %s" % src_wp)
    pack_caml, pack_root, groups = parse_root(src_ca)
    m = re.match(r"0 0 ([0-9.]+) ([0-9.]+)", pack_root.get("bounds", "0 0 393 852"))
    src_w, src_h = (float(m.group(1)), float(m.group(2))) if m else (393.0, 852.0)

    mapping = [("BACKGROUND", "Background"), ("FOREGROUND", "Foreground"), ("FLOATING", "Floating")]
    os.makedirs(out_wp, exist_ok=True)
    ca_names = {}
    for gid, published in mapping:
        ca_name = "%s.ca" % published
        ca_dir = os.path.join(out_wp, ca_name)
        if os.path.isdir(ca_dir):
            shutil.rmtree(ca_dir)
        os.makedirs(os.path.join(ca_dir, "assets"), exist_ok=True)
        # main.caml
        doc = build_layer_doc(pack_caml, pack_root, groups.get(gid), published, src_w, src_h)
        ET.ElementTree(doc).write(os.path.join(ca_dir, "main.caml"), encoding="UTF-8", xml_declaration=True)
        # index.xml / manifest
        open(os.path.join(ca_dir, "index.xml"), "w").write(NATIVE_INDEX.replace("{PUBLISHED}", published))
        open(os.path.join(ca_dir, "assetManifest.caml"), "w").write(ASSET_MANIFEST)
        # assets (copy everything; CAML refs assets/<file>)
        src_assets = os.path.join(src_ca, "assets")
        if os.path.isdir(src_assets):
            for f in os.listdir(src_assets):
                s = os.path.join(src_assets, f)
                if os.path.isfile(s):
                    shutil.copy2(s, os.path.join(ca_dir, "assets", f))
        ca_names[published] = ca_name

    # Wallpaper.plist (iOS 16 LayeredAnimation)
    wp = {"appearanceAware": False,
          "assets": {"lockAndHome": {"default": {
              "type": "LayeredAnimation",
              "identifier": 7920,
              "name": name or "Tendie",
              "backgroundAnimationFileName": ca_names["Background"],
              "foregroundAnimationFileName": ca_names["Foreground"],
              "floatingAnimationFileNameKey": ca_names["Floating"],
          }}},
          "family": "WWDC22",
          "identifier": 7920,
          "logicalScreenClass": "414w-736h@3x~iphone",
          "name": name or "Tendie",
          "productTypes": ["iPhone10,5"],
          "version": 1,
          "wantsDeviceMotion": True,
          "preferredProminentColor": {"default": "#FFFFFF"},
          "preferredTitleColor": ["#FFFFFF02"]}
    if ident:
        wp["identifier"] = ident
    plistlib.dump(wp, open(os.path.join(out_wp, "Wallpaper.plist"), "wb"), fmt=plistlib.FMT_BINARY)
    return ca_names

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(2)
    src, out = sys.argv[1], sys.argv[2]
    ident = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else None
    name = sys.argv[4] if len(sys.argv) > 4 else None
    print(convert(src, out, ident, name))
