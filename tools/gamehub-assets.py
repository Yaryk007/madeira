#!/usr/bin/env python3
"""GamehubiOS: GameHub's own logo and icons, fetched at build time.

The artwork belongs to XiaoJi, so the repository does not carry it. This
script downloads the official GameHub APK (the URL GameHub's website gives,
gamehub.xiaoji.com/en/download/apk/config), takes the images listed in ASSETS
from its Compose resources and writes them into
app/Madeira/Assets.xcassets/GameHub (git-ignored). Android vector drawables
become SVG image sets; PNG and WebP become PNG image sets. The app falls back
to SF Symbols for any image that is missing, so a build without this step
still works.

    python3 tools/gamehub-assets.py [--apk path/to/GameHub.apk]
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile, urllib.request, zipfile
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "app", "Madeira", "Assets.xcassets", "GameHub")
CONFIG = "https://gamehub.xiaoji.com/en/download/apk/config"
RES = "assets/composeResources/com.xiaoji.egggame."
# GameHub's iOS app (id6717579482), for its 1024 px icon; the CI step then
# points ASSETCATALOG_COMPILER_APPICON_NAME at APPICON.
ITUNES = "https://itunes.apple.com/lookup?id=6717579482&country=us"
APPICON = "GameHubAppIcon"

# asset name -> (resource path under composeResources, template rendering)
ASSETS = {
    "gh-logo-mark":       ("features.onboarding/drawable/ic_onboarding_logo.png", False),
    "gh-logo-wordmark":   ("features.auth/drawable/features_auth_ic_logo_overseas.png", False),
    "gh-logo-small":      ("features.auth/drawable/features_auth_ic_logo_landscape.png", False),
    "gh-logo-splash":     ("features.splash/drawable/splash_logo.webp", False),
    "gh-nav-library":     ("core/drawable/core_nav_library_default.xml", False),
    "gh-nav-library-on":  ("core/drawable/core_nav_library_selected.xml", False),
    "gh-nav-community":   ("core/drawable/core_nav_community_default.xml", False),
    "gh-nav-community-on": ("core/drawable/core_nav_community_selected.xml", False),
    "gh-nav-home":        ("core/drawable/core_nav_home_default.xml", False),
    "gh-nav-home-on":     ("core/drawable/core_nav_home_selected.xml", False),
    "gh-nav-ranking":     ("core/drawable/core_nav_ranking_default.xml", False),
    "gh-nav-ranking-on":  ("core/drawable/core_nav_ranking_selected.xml", False),
    "gh-nav-profile":     ("core/drawable/core_nav_profile_default.xml", False),
    "gh-nav-profile-on":  ("core/drawable/core_nav_profile_selected.xml", False),
    "gh-bell":            ("core/drawable/core_ic_message_center.xml", False),
    "gh-settings-hex":    ("core/drawable/core_icon_settings_hex.xml", False),
    "gh-empty":           ("core/drawable/core_empty_data.xml", False),
    "gh-gamepad":         ("core/drawable/ic_home_device.png", False),
    "gh-layout-switch":   ("core/drawable/ic_home_layoutswitch.png", False),
    "gh-wifi":            ("core/drawable/ic_home_wifi.png", False),
    "gh-no-network":      ("core/drawable/ic_home_no_network.png", False),
    "gh-5g":              ("core/drawable/ic_home_5g.png", False),
    "gh-battery-1":       ("core/drawable/ic_battery_level1.png", False),
    "gh-battery-2":       ("core/drawable/ic_battery_level2.png", False),
    "gh-battery-3":       ("core/drawable/ic_battery_level3.png", False),
    "gh-battery-4":       ("core/drawable/ic_battery_level4.png", False),
    "gh-battery-5":       ("core/drawable/ic_battery_level5.png", False),
    "gh-lb":              ("core/drawable/common_icon_lb.png", False),
    "gh-rb":              ("core/drawable/common_icon_rb.png", False),
    "gh-search":          ("features.home/drawable/features_home_library_ic_search.png", False),
    "gh-entry-mygames":   ("features.home/drawable/features_home_library_entry_my_games.png", False),
    "gh-entry-steam":     ("features.home/drawable/features_home_library_entry_steam.png", False),
    "gh-entry-epic":      ("features.home/drawable/features_home_library_entry_epic.png", False),
    "gh-import":          ("features.home/drawable/features_home_library_ic_import.png", False),
    "gh-guest-warning":   ("features.home/drawable/features_home_ic_guest_warning.png", False),
    "gh-guest-social":    ("features.home/drawable/features_home_ic_guest_social.png", False),
    "gh-avatar":          ("features.home/drawable/unlogin_avatar_default.png", False),
    "gh-download":        ("features.home/drawable/features_home_profile_ic_download.png", False),
    "gh-settings":        ("features.home/drawable/features_home_profile_ic_settings.png", False),
    "gh-qr":              ("features.home/drawable/features_home_mine_qr_scanner.xml", False),
    "gh-no-data":         ("features.home/drawable/no_data_list.png", False),
    "gh-keyboard":        ("features.vjoy/drawable/features_vjoy_keyboard.xml", True),
}

A = "{http://schemas.android.com/apk/res/android}"
AAPT = "{http://schemas.android.com/aapt}"


def color(value, alpha=1.0):
    """#RGB, #ARGB, #RRGGBB or #AARRGGBB -> (rgb hex, opacity)."""
    v = value.strip().lstrip("#")
    if len(v) in (3, 4): v = "".join(c * 2 for c in v)
    a = 1.0
    if len(v) == 8: a, v = int(v[:2], 16) / 255, v[2:]
    return "#" + v, a * alpha


def num(el, name, default):
    v = el.get(A + name)
    return float(v.rstrip("dp")) if v is not None else default


def vector_to_svg(data):
    root = ET.fromstring(data)
    w, h = num(root, "width", 24), num(root, "height", 24)
    vw, vh = num(root, "viewportWidth", w), num(root, "viewportHeight", h)
    defs, body, counter = [], [], [0]

    def gradient(attr_el):
        g = attr_el.find("gradient")
        if g is None: return None
        counter[0] += 1
        gid = f"g{counter[0]}"
        stops = []
        items = g.findall("item")
        if items:
            for it in items:
                c, a = color(it.get(A + "color"))
                stops.append(f'<stop offset="{it.get(A + "offset")}" stop-color="{c}" stop-opacity="{a:.3f}"/>')
        else:
            for off, key in (("0", "startColor"), ("0.5", "centerColor"), ("1", "endColor")):
                if g.get(A + key):
                    c, a = color(g.get(A + key))
                    stops.append(f'<stop offset="{off}" stop-color="{c}" stop-opacity="{a:.3f}"/>')
        if g.get(A + "type", "linear") == "radial":
            defs.append(f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{g.get(A + "centerX", "0")}" '
                        f'cy="{g.get(A + "centerY", "0")}" r="{g.get(A + "gradientRadius", "1")}">{"".join(stops)}</radialGradient>')
        else:
            defs.append(f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{g.get(A + "startX", "0")}" '
                        f'y1="{g.get(A + "startY", "0")}" x2="{g.get(A + "endX", "0")}" y2="{g.get(A + "endY", "0")}">'
                        f'{"".join(stops)}</linearGradient>')
        return f"url(#{gid})"

    def path(el):
        attrs = [f'd="{el.get(A + "pathData")}"']
        fill = el.get(A + "fillColor")
        for attr in el.findall(AAPT + "attr"):
            ref = gradient(attr)
            if ref and attr.get("name") == "android:fillColor": fill = ref
            elif ref and attr.get("name") == "android:strokeColor":
                attrs.append(f'stroke="{ref}" stroke-width="{num(el, "strokeWidth", 0)}"')
        if fill and fill.startswith("url("):
            attrs.append(f'fill="{fill}"')
        elif fill:
            c, a = color(fill, num(el, "fillAlpha", 1))
            attrs.append(f'fill="{c}" fill-opacity="{a:.3f}"')
        else:
            attrs.append('fill="none"')
        if el.get(A + "fillType") == "evenOdd": attrs.append('fill-rule="evenodd"')
        stroke = el.get(A + "strokeColor")
        if stroke:
            c, a = color(stroke, num(el, "strokeAlpha", 1))
            attrs.append(f'stroke="{c}" stroke-opacity="{a:.3f}" stroke-width="{num(el, "strokeWidth", 0)}"')
            if el.get(A + "strokeLineCap"): attrs.append(f'stroke-linecap="{el.get(A + "strokeLineCap")}"')
            if el.get(A + "strokeLineJoin"): attrs.append(f'stroke-linejoin="{el.get(A + "strokeLineJoin")}"')
        return f'<path {" ".join(attrs)}/>'

    def walk(el, out):
        for child in el:
            if child.tag == "path": out.append(path(child))
            elif child.tag == "clip-path":
                counter[0] += 1
                defs.append(f'<clipPath id="c{counter[0]}"><path d="{child.get(A + "pathData")}"/></clipPath>')
                out.append(f'<g clip-path="url(#c{counter[0]})">')
                out.append(None)  # closed by the group that holds it
            elif child.tag == "group":
                px, py = num(child, "pivotX", 0), num(child, "pivotY", 0)
                t = (f'translate({num(child, "translateX", 0) + px} {num(child, "translateY", 0) + py}) '
                     f'rotate({num(child, "rotation", 0)}) scale({num(child, "scaleX", 1)} {num(child, "scaleY", 1)}) '
                     f'translate({-px} {-py})')
                inner = []
                walk(child, inner)
                opened = sum(1 for x in inner if x is None)
                out.append(f'<g transform="{t}">' + "".join(x for x in inner if x) + "</g>" * opened + "</g>")
        return out

    parts = walk(root, [])
    opened = sum(1 for x in parts if x is None)
    content = "".join(x for x in parts if x) + "</g>" * opened
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {vw} {vh}">'
            f'<defs>{"".join(defs)}</defs>{content}</svg>')


def to_png(src, dst):
    """WebP -> PNG with sips (macOS) or ffmpeg."""
    for cmd in (["sips", "-s", "format", "png", src, "--out", dst], ["ffmpeg", "-v", "error", "-y", "-i", src, dst]):
        if shutil.which(cmd[0]) and subprocess.run(cmd, capture_output=True).returncode == 0 and os.path.exists(dst):
            return True
    return False


def write_set(name, filename, data, template, vector):
    folder = os.path.join(OUT, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, filename), "wb") as f: f.write(data)
    props = {}
    if vector: props["preserves-vector-representation"] = True
    if template: props["template-rendering-intent"] = "template"
    contents = {"images": [{"filename": filename, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    if props: contents["properties"] = props
    with open(os.path.join(folder, "Contents.json"), "w") as f: json.dump(contents, f, indent=2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", help="a GameHub APK already on disk (otherwise the official one is downloaded)")
    args = parser.parse_args()
    work = tempfile.mkdtemp(prefix="gamehub-assets-")
    apk = args.apk
    if not apk:
        req = urllib.request.Request(CONFIG, headers={"User-Agent": "Mozilla/5.0"})
        url = json.load(urllib.request.urlopen(req, timeout=60))["data"]["download_url"]
        apk = os.path.join(work, "GameHub.apk")
        print("downloading", url)
        urllib.request.urlretrieve(url, apk)
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    written = 0
    with zipfile.ZipFile(apk) as z:
        names = set(z.namelist())
        for name, (path, template) in ASSETS.items():
            member = RES + path
            if member not in names:
                print("missing", path); continue
            data = z.read(member)
            ext = path.rsplit(".", 1)[1]
            if ext == "xml":
                write_set(name, name + ".svg", vector_to_svg(data).encode(), template, True)
            elif ext == "png":
                write_set(name, name + ".png", data, template, False)
            else:
                src, dst = os.path.join(work, name + "." + ext), os.path.join(work, name + ".png")
                with open(src, "wb") as f: f.write(data)
                if not to_png(src, dst):
                    print("could not convert", path); continue
                with open(dst, "rb") as f: write_set(name, name + ".png", f.read(), template, False)
            written += 1
    # The app icon: GameHub's own, 1024 px, from its App Store listing (Apple's iTunes lookup).
    try:
        lookup = json.load(urllib.request.urlopen(ITUNES, timeout=60))["results"][0]["artworkUrl512"]
        art = urllib.request.urlopen(re.sub(r"/\d+x\d+bb\.\w+$", "/1024x1024bb.png", lookup), timeout=60).read()
        folder = os.path.join(OUT, APPICON + ".appiconset")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "AppIcon.png"), "wb") as f: f.write(art)
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                       "info": {"author": "xcode", "version": 1}}, f, indent=2)
        print("app icon:", APPICON)
    except Exception as e:
        print("app icon unavailable:", e)
    shutil.rmtree(work, ignore_errors=True)
    print(f"GameHub assets: {written}/{len(ASSETS)} written to {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
