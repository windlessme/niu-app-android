#!/usr/bin/env python3
"""Render each floor of a campus-map building JSON to PNG for review.

    python3 tool/preview_campus_map.py ../app-content/campus-map/jiaose.json OUT_DIR [--portrait]

--portrait turns landscape buildings 90° clockwise, as phones show them.
--labels writes each room's code and name, and links to other buildings,
for checking against the signs.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"

PX = 22  # pixels per metre
SS = 3  # supersampling
PAD = 3.0  # metres around the building; --labels adds room for link signs

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


def wrap(text, font, width, draw):
    """Lines of text no wider than width, breaking anywhere (CJK)."""
    lines, line = [], ""
    for ch in text:
        if line and draw.textlength(line + ch, font=font) > width:
            lines.append(line)
            line = ch
        else:
            line += ch
    return [*lines, line] if line else lines


def inside(poly, x, y):
    hit = False
    for (xi, yi), (xj, yj) in zip(poly, poly[-1:] + poly[:-1]):
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
    return hit


def label_box(space):
    """The largest upright rectangle inside a room, where the apps put its
    label (an L-shaped room's bounding box centre may be outside it)."""
    pts = points(space)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    if "rect" in space:
        return x0, y0, x1, y1
    n = 32
    cw, ch = (x1 - x0) / n, (y1 - y0) / n
    heights, best, area = [0] * n, (x0, y0, x1, y1), 0
    for row in range(n):
        for col in range(n):
            heights[col] = heights[col] + 1 if inside(pts, x0 + (col + .5) * cw, y0 + (row + .5) * ch) else 0
        for col in range(n):
            h = heights[col]
            for end in range(col, n):
                h = min(h, heights[end])
                if not h:
                    break
                if (end + 1 - col) * h > area:
                    area = (end + 1 - col) * h
                    best = (x0 + col * cw, y0 + (row + 1 - h) * ch, x0 + (end + 1) * cw, y0 + (row + 1) * ch)
    return best


def label(d, floor, pt):
    for s in floor["spaces"]:
        text = [t for t in (s.get("code"), s.get("name"), s.get("note")) if t]
        if not text or s["kind"] in ("corridor",):
            continue
        bx0, by0, bx1, by1 = label_box(s)
        (a, b), (c, e) = pt(bx0, by0), pt(bx1, by1)
        width, height = c - a - 6 * SS, e - b - 6 * SS
        for size in (13, 11, 9, 8, 7):
            fonts = [ImageFont.truetype(FONT, (size + (2 if i == 0 and s.get("code") else 0)) * SS)
                     for i in range(len(text))]
            lines = [(f, l) for f, t in zip(fonts, text) for l in wrap(t, f, width, d)]
            total = sum(f.size * 1.15 for f, _ in lines)
            if total <= height:
                break
        y = (b + e) / 2 - total / 2
        for f, l in lines:
            d.text(((a + c) / 2, y), l, font=f, fill=(40, 52, 80), anchor="ma")
            y += f.size * 1.15
    for link in floor.get("links", []):
        x, y = pt(*link["at"])
        dx, dy = link["toward"]
        f = ImageFont.truetype(FONT, 12 * SS)
        d.text((x + dx * 8 * SS, y + dy * 8 * SS), f"往{link['name']} →", font=f, fill=(180, 60, 40),
               anchor="lm" if dx > 0 else "rm")


CLOSED = (214, 69, 65)


def midpoint(line):
    """The point halfway along a polyline."""
    steps = [((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** .5 for a, b in zip(line, line[1:])]
    left = sum(steps) / 2
    for (a, b), step in zip(zip(line, line[1:]), steps):
        if left <= step and step:
            t = left / step
            return a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        left -= step
    return tuple(line[-1])


def draw_closed(d, line, pt):
    """A door no one may pass: a red bar across it, crossed out."""
    d.line([pt(*p) for p in line], fill=CLOSED, width=4 * SS, joint="curve")
    x, y = midpoint(line)
    r = 0.6
    d.line([pt(x - r, y - r), pt(x + r, y + r)], fill=CLOSED, width=3 * SS)
    d.line([pt(x + r, y - r), pt(x - r, y + r)], fill=CLOSED, width=3 * SS)


def render(floor, out, portrait, labels=False):
    global PAD
    PAD = 7.0 if labels else 3.0
    rings = floor.get("outlines") or [floor["outline"]]
    allpts = [tuple(p) for r in rings for p in r] + [p for s in floor["spaces"] for p in points(s)]
    minx, miny = min(p[0] for p in allpts), min(p[1] for p in allpts)
    maxx, maxy = max(p[0] for p in allpts), max(p[1] for p in allpts)
    w = int((maxx - minx + PAD * 2) * PX * SS)
    h = int((maxy - miny + PAD * 2) * PX * SS)

    def pt(x, y):
        return ((x - minx + PAD) * PX * SS, (y - miny + PAD) * PX * SS)

    img = Image.new("RGB", (w, h), CANVAS)
    outlines = [[pt(*p) for p in r] for r in rings]
    shadow = Image.new("L", img.size, 0)
    for outline in outlines:
        ImageDraw.Draw(shadow).polygon([(a, b + 6 * SS) for a, b in outline], fill=60)
    shadow = shadow.filter(ImageFilter.GaussianBlur(10 * SS))
    img.paste((205, 211, 222), mask=shadow)
    d = ImageDraw.Draw(img)
    for outline in outlines:
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
    for line in floor.get("closed", []):
        draw_closed(d, line, pt)
    if labels:
        label(d, floor, pt)
        f = ImageFont.truetype(FONT, 20 * SS)
        d.text((12 * SS, 10 * SS), floor["id"], font=f, fill=(40, 52, 80))
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
        render(floor, path, portrait, "--labels" in sys.argv)
        print(path)


if __name__ == "__main__":
    main()
