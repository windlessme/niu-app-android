#!/usr/bin/env python3
"""Render each floor of a campus-map building JSON to PNG for review.

    python3 tool/preview_campus_map.py ../app-content/campus-map/jiaose.json OUT_DIR [--portrait]

--portrait turns landscape buildings 90° clockwise, as phones show them.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PX = 22  # pixels per metre
SS = 3  # supersampling
PAD = 3.0  # metres around the building

CANVAS = (238, 241, 246)
SLAB = (250, 251, 253)
SLAB_EDGE = (214, 219, 228)
STYLE = {
    "terrace": ((232, 240, 230), (214, 226, 210)),
    "corridor": ((255, 255, 255), None),
    "void": ((238, 241, 246), (206, 212, 222)),
    "room": ((233, 239, 251), (190, 205, 235)),
    "restroom": ((229, 240, 239), (196, 218, 215)),
    "stairs": ((226, 229, 235), (204, 208, 216)),
    "elevator": ((214, 218, 226), (196, 201, 211)),
}
ORDER = list(STYLE)
GAP = 0.18  # metres between neighbouring tiles
RADIUS = 0.45


def points(space):
    if "rect" in space:
        x, y, w, h = space["rect"]
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    return [tuple(p) for p in space["polygon"]]


def convex(pts):
    signs = set()
    for i in range(len(pts)):
        (ax, ay), (bx, by), (cx, cy) = pts[i - 2], pts[i - 1], pts[i]
        cross = (bx - ax) * (cy - by) - (by - ay) * (cx - bx)
        if abs(cross) > 1e-9:
            signs.add(cross > 0)
    return len(signs) <= 1


def inset(pts, d):
    """Shrink a convex polygon towards its centroid; concave ones stay as is."""
    if not convex(pts):
        return pts
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    out = []
    for x, y in pts:
        dx, dy = cx - x, cy - y
        n = max((dx * dx + dy * dy) ** 0.5, 1e-6)
        out.append((x + dx / n * d * 1.4, y + dy / n * d * 1.4))
    return out


def render(floor, out, portrait):
    allpts = [tuple(p) for p in floor["outline"]] + [p for s in floor["spaces"] for p in points(s)]
    minx, miny = min(p[0] for p in allpts), min(p[1] for p in allpts)
    maxx, maxy = max(p[0] for p in allpts), max(p[1] for p in allpts)
    w = int((maxx - minx + PAD * 2) * PX * SS)
    h = int((maxy - miny + PAD * 2) * PX * SS)

    def pt(x, y):
        return ((x - minx + PAD) * PX * SS, (y - miny + PAD) * PX * SS)

    img = Image.new("RGB", (w, h), CANVAS)
    outline = [pt(*p) for p in floor["outline"]]
    shadow = Image.new("L", img.size, 0)
    ImageDraw.Draw(shadow).polygon([(a, b + 6 * SS) for a, b in outline], fill=60)
    shadow = shadow.filter(ImageFilter.GaussianBlur(10 * SS))
    img.paste((205, 211, 222), mask=shadow)
    d = ImageDraw.Draw(img)
    d.polygon(outline, fill=SLAB, outline=SLAB_EDGE, width=2 * SS)

    for kind in ORDER:
        fill, stroke = STYLE[kind]
        for s in floor["spaces"]:
            if s["kind"] != kind:
                continue
            flat = kind in ("corridor", "terrace")
            pts = points(s)
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
            if "rect" in s and not flat:
                a, b = pt(x0 + GAP, y0 + GAP)
                c, e = pt(x1 - GAP, y1 - GAP)
                d.rounded_rectangle([a, b, c, e], radius=RADIUS * PX * SS, fill=fill,
                                    outline=stroke, width=SS * 2 if stroke else 0)
            else:
                poly = [pt(*p) for p in (pts if flat else inset(pts, GAP))]
                d.polygon(poly, fill=fill, outline=stroke, width=SS * 2 if stroke else 0)
            if kind == "stairs":
                horizontal = (x1 - x0) >= (y1 - y0)
                t = (x0 if horizontal else y0) + 0.8
                end = (x1 if horizontal else y1) - 0.8
                while t < end:
                    line = [pt(t, y0 + 0.5), pt(t, y1 - 0.5)] if horizontal else [pt(x0 + 0.5, t), pt(x1 - 0.5, t)]
                    d.line(line, fill=stroke, width=SS)
                    t += 0.45
            if kind in ("elevator", "void"):
                m = 0.4 if kind == "elevator" else 0.8
                d.line([pt(x0 + m, y0 + m), pt(x1 - m, y1 - m)], fill=stroke, width=SS)
                d.line([pt(x1 - m, y0 + m), pt(x0 + m, y1 - m)], fill=stroke, width=SS)
    img = img.resize((w // SS, h // SS), Image.LANCZOS)
    if portrait and img.width > img.height:
        img = img.rotate(-90, expand=True)
    img.save(out)


def main():
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = Path(sys.argv[2])
    portrait = "--portrait" in sys.argv
    out.mkdir(parents=True, exist_ok=True)
    for floor in data["floors"]:
        path = out / f"{data['id']}-{floor['id']}.png"
        render(floor, path, portrait)
        print(path)


if __name__ == "__main__":
    main()
