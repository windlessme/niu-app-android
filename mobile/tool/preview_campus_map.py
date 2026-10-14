#!/usr/bin/env python3
"""Render each floor of a campus-map building JSON to PNG for review.

    python3 tool/preview_campus_map.py ../app-content/campus-map/jiaose.json OUT_DIR
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PX = 22  # pixels per metre
SS = 3  # supersampling
PAD = 2.0  # metres around the building

CANVAS = (238, 241, 246)
SLAB = (250, 251, 253)
SLAB_EDGE = (214, 219, 228)
STYLE = {
    "room": ((233, 239, 251), (190, 205, 235)),
    "corridor": ((255, 255, 255), None),
    "stairs": ((226, 229, 235), (204, 208, 216)),
    "elevator": ((214, 218, 226), (196, 201, 211)),
    "restroom": ((229, 240, 239), (196, 218, 215)),
    "void": ((238, 241, 246), (214, 219, 228)),
}
GAP = 0.18  # metres between neighbouring tiles
RADIUS = 0.45


def rect_of(space):
    x, y, w, h = space["rect"]
    return x, y, x + w, y + h


def render(floor, out):
    xs = [p[0] for p in floor["outline"]]
    ys = [p[1] for p in floor["outline"]]
    w = (max(xs) - min(xs) + PAD * 2) * PX * SS
    h = (max(ys) - min(ys) + PAD * 2) * PX * SS
    ox, oy = PAD - min(xs), PAD - min(ys)

    def pt(x, y):
        return ((x + ox) * PX * SS, (y + oy) * PX * SS)

    img = Image.new("RGB", (int(w), int(h)), CANVAS)
    # Soft shadow under the slab.
    shadow = Image.new("L", img.size, 0)
    ImageDraw.Draw(shadow).polygon(
        [(a, b + 6 * SS) for a, b in (pt(*p) for p in floor["outline"])], fill=60
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(10 * SS))
    img.paste((205, 211, 222), mask=shadow)
    d = ImageDraw.Draw(img)
    d.polygon([pt(*p) for p in floor["outline"]], fill=SLAB, outline=SLAB_EDGE, width=2 * SS)

    order = ["corridor", "void", "room", "restroom", "stairs", "elevator"]
    for kind in order:
        fill, stroke = STYLE[kind]
        for s in floor["spaces"]:
            if s["kind"] != kind:
                continue
            x0, y0, x1, y1 = rect_of(s)
            g = 0 if kind == "corridor" else GAP
            a, b = pt(x0 + g, y0 + g)
            c, e = pt(x1 - g, y1 - g)
            d.rounded_rectangle(
                [a, b, c, e],
                radius=(0 if kind == "corridor" else RADIUS) * PX * SS,
                fill=fill,
                outline=stroke,
                width=SS * 2 if stroke else 0,
            )
            if kind == "stairs":
                horizontal = (x1 - x0) >= (y1 - y0)
                step = 0.45
                if horizontal:
                    t = x0 + 0.8
                    while t < x1 - 0.8:
                        d.line([pt(t, y0 + 0.5), pt(t, y1 - 0.5)], fill=stroke, width=SS)
                        t += step
                else:
                    t = y0 + 0.8
                    while t < y1 - 0.8:
                        d.line([pt(x0 + 0.5, t), pt(x1 - 0.5, t)], fill=stroke, width=SS)
                        t += step
            if kind == "elevator":
                d.line([pt(x0 + 0.4, y0 + 0.4), pt(x1 - 0.4, y1 - 0.4)], fill=stroke, width=SS)
                d.line([pt(x1 - 0.4, y0 + 0.4), pt(x0 + 0.4, y1 - 0.4)], fill=stroke, width=SS)
    img = img.resize((int(w / SS), int(h / SS)), Image.LANCZOS)
    img.save(out)


def main():
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for floor in data["floors"]:
        path = out / f"{data['id']}-{floor['id']}.png"
        render(floor, path)
        print(path)


if __name__ == "__main__":
    main()
