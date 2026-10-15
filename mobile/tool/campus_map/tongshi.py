#!/usr/bin/env python3
"""Generates app-content/campus-map/tongshi.json (通識教育中心).

Two floors, from two kinds of sign in the building. 「通識教育中心無障礙地圖」
draws both floors to scale, north up with the street (人行道) to the south;
its walls give the geometry, fitted to the 39.4 × 13 m OpenStreetMap
outline by four corners, which also takes out the photo's slant. The
directory signs on each floor (「求真樓一樓／二樓平面圖」, also north up)
give the room numbers and who is in each room: they number the rooms 求101,
求102 … so that is the code. Where the two disagree the directory wins: the
room the accessibility map calls 茶水室 is 求107 兼任教師休息室 on 1F and 求209
教材準備室 on 2F.

The outline's two southern bulges are 求101 (it runs the full depth on the
directory, beside the 花台 that fills the recess between) and the stair
hall at the east end. 2F has no west bulge: its corridor runs along the
whole south side.
"""
import json
from pathlib import Path

UNIT = "通識教育中心"
ALIASES = ["通識中心", "通識"]

# OpenStreetMap way 256119629, its bounding box's north-west corner at 0, 0.
OUTLINE = [[0, 0.5], [39.2, 0], [39.4, 13.0], [30.6, 13.1], [30.5, 11.0], [8.5, 11.3], [8.6, 12.6], [0.2, 12.7]]


def solve(a, b):
    """Gaussian elimination for a small dense system."""
    n = len(b)
    m = [row[:] + [v] for row, v in zip(a, b)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                m[r] = [x - f * y for x, y in zip(m[r], m[c])]
    return [m[r][n] / m[r][r] for r in range(n)]


class Sign:
    """One floor of the accessibility map: its outer walls' four corners in
    photo pixels and where they are in metres (east, south), as a projective
    map. The south corners sit on the line of the recess between the
    outline's bulges."""

    def __init__(self, nw, ne, se, sw):
        pairs = [(nw, (0, 0.5)), (ne, (39.2, 0)), (se, (39.3, 10.9)), (sw, (0.1, 11.4))]
        a, b = [], []
        for (u, v), (x, y) in pairs:
            a.append([u, v, 1, 0, 0, 0, -u * x, -v * x])
            b.append(x)
            a.append([0, 0, 0, u, v, 1, -u * y, -v * y])
            b.append(y)
        self.h = solve(a, b)

    def pt(self, u, v):
        h = self.h
        w = h[6] * u + h[7] * v + 1
        return [round((h[0] * u + h[1] * v + h[2]) / w, 2), round((h[3] * u + h[4] * v + h[5]) / w, 2)]

    def pts(self, ps):
        return [p if isinstance(p, list) else self.pt(*p) for p in ps]

    def poly(self, kind, ps, code=None, name=None):
        return labelled({"kind": kind, "polygon": self.pts(ps)}, code, name)

    def rect(self, kind, u0, v0, u1, v1, code=None, name=None):
        """A box on the sign: a rectangle in metres unless the slant skews
        it noticeably."""
        ps = self.pts([(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
        xs, ys = [p[0] for p in ps], [p[1] for p in ps]
        area = abs(sum(p[0] * q[1] - q[0] * p[1] for p, q in zip(ps, ps[1:] + ps[:1]))) / 2
        x0, y0 = min(xs), min(ys)
        if area > .96 * (max(xs) - x0) * (max(ys) - y0):
            space = {"kind": kind, "rect": [x0, y0, round(max(xs) - x0, 2), round(max(ys) - y0, 2)]}
        else:
            space = {"kind": kind, "polygon": ps}
        return labelled(space, code, name)

    def room(self, *box, code=None, name=None):
        return self.rect("room", *box, code=code, name=name)


def labelled(space, code, name):
    if code:
        space["code"] = f"求{code}"
    if name:
        space["name"] = name
    return space


def floor_1f():
    # Pixels in IMG_6036 (1600 px long side); the outer walls run
    # 382–1230 across and 219–460 down.
    g = Sign((382, 219), (1230, 219), (1230, 460), (382, 460))
    n, s = 219, 404  # the outer north wall; the rooms' south wall
    spaces = [
        g.rect("corridor", 725, n, 786, s),
        g.poly("corridor", [(593, s), (1140, s), (1140, 500), (1105, 500), (1105, 460), (593, 460)]),
        g.rect("corridor", 1105, 350, 1185, s),
        g.rect("elevator", 1185, 350, 1230, s),
        g.rect("stairs", 1140, s, 1230, 500),
        g.rect("restroom", 1105, n, 1230, 310, name="女廁"),
        g.rect("restroom", 1105, 310, 1160, 350, name="無障礙廁所"),
        g.rect("restroom", 1160, 310, 1230, 350, name="男廁"),
        g.room(382, n, 593, 302, name="中心主任辦公室"),
        # 求101 runs the full depth, into the outline's west bulge.
        g.poly("room", [(382, 302), (593, 302), (593, 460), [8.5, 11.3], [8.6, 12.6], [0.2, 12.7], (382, 460)],
               code="101", name="通識教育中心辦公室"),
        g.room(593, n, 725, 316, code="103", name="吳鳳珠老師"),
        g.room(593, 316, 725, s, code="102", name="劉怡伶老師"),
        g.room(786, n, 917.5, 316, code="104", name="徐明藤老師"),
        g.room(786, 316, 917.5, s, code="105", name="楊淳凱老師"),
        g.room(917.5, n, 1045, s, code="106", name="會議室"),
        g.room(1045, n, 1105, s, code="107", name="兼任教師休息室"),
    ]
    return {"id": "1F", "outline": OUTLINE, "spaces": spaces}


def floor_2f():
    g = Sign((376, 695), (1252, 688), (1252, 933), (376, 933))

    def n(u):
        """The north wall, which the photo tilts a little."""
        return round(695 - 7 * (u - 376) / 876, 1)

    s = 870  # the rooms' south wall
    spaces = [
        g.rect("corridor", 527, n(527), 593, s),
        g.rect("corridor", 860, n(860), 922, s),
        g.rect("corridor", 376, s, 1125, 933),
        g.rect("corridor", 1120, 800, 1205, s),
        g.rect("elevator", 1205, 800, 1252, s),
        g.rect("stairs", 1125, s, 1252, 960),
        g.rect("restroom", 1120, n(1120), 1252, 765, name="女廁"),
        g.rect("restroom", 1120, 765, 1252, 800, name="男廁"),
        g.room(376, n(376), 527, 784, code="202", name="張松年老師"),
        g.room(376, 784, 527, s, code="201", name="蔣忠慈老師"),
        g.room(593, n(593), 727, 777, code="203", name="楊淳皓老師"),
        g.room(593, 777, 727, s, code="204", name="許惠琪老師"),
        g.room(727, n(727), 860, 777, code="206", name="錢芷萍老師"),
        g.room(727, 777, 860, s, code="205", name="陳雀倩老師"),
        g.room(922, n(922), 1060, 775, code="207", name="邵維慶老師"),
        g.room(922, 775, 1060, s, code="208", name="討論室"),
        g.room(1060, n(1060), 1120, s, code="209", name="教材準備室"),
    ]
    stair_w = g.pt(1125, 960)[0]
    outline = [[0, 0.5], [39.2, 0], [39.4, 13.0], [stair_w, 13.0], g.pt(1125, 933), [0.1, 11.4]]
    return {"id": "2F", "outline": outline, "spaces": spaces}


def main():
    building = {
        "id": "tongshi",
        "name": "通識教育中心",
        "unit": "m",
        "floors": [floor_1f(), floor_2f()],
    }
    for floor in building["floors"]:
        floor["unit"] = UNIT
        floor["aliases"] = ALIASES
        for space in floor["spaces"]:
            if space.get("name") == "中心主任辦公室":
                space["note"] = UNIT
        codes = [s["code"] for s in floor["spaces"] if "code" in s]
        assert len(codes) == len(set(codes)), (floor["id"], codes)
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/tongshi.json", root / "mobile/assets/campus_map/tongshi.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
