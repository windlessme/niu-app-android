#!/usr/bin/env python3
"""Generates app-content/campus-map/zonghe.json (綜合教學大樓).

Measured from the evacuation maps on each floor and scaled to the
OpenStreetMap outline: two 64 × 14 m wings 25 m apart, joined on 3F by a
corridor. The signs hang upside down (往行政大樓 is on their left, and 行政大樓
is east), so their top wing is the south wing and plans turn half round to
north up. 1F's east end is the open 川堂; 1F and 2F lead on to 行政大樓.
"""
import json
from pathlib import Path

L, DEPTH = 64.0, 14.0
SOUTH = (39.0, 53.0)  # the signs' top wing
NORTH = (0.0, 14.0)  # the signs' bottom wing


class Wing:
    """One wing of one sign: pixel x of its west (right) and east (left)
    ends, pixel y of its top and bottom edges, and where it is in metres."""

    def __init__(self, west, east, top, bottom, band):
        self.west, self.east, self.top, self.bottom, self.band = west, east, top, bottom, band

    def x(self, px):
        return round(L * (self.west - px) / (self.west - self.east), 2)

    def y(self, py):
        # Upside down: the sign's top edge is the wing's south edge.
        t = (py - self.top) / (self.bottom - self.top)
        return round(self.band[1] - t * DEPTH, 2)

    def rect(self, kind, box, code=None, name=None):
        x0, y0, x1, y1 = box
        a, c = sorted((self.x(x0), self.x(x1)))
        b, d = sorted((self.y(y0), self.y(y1)))
        space = {"kind": kind, "rect": [a, b, round(c - a, 2), round(d - b, 2)]}
        if code:
            space["code"] = f"綜{code}"
        if name:
            space["name"] = name
        return space

    def room(self, box, code, name="教室"):
        return self.rect("room", box, code, name)


# The 3F corridor between the wings, from the sign (near the east end).
LINK = (51.5, 56.3)


def outline(connector=False):
    """Both wings as one outline; floors without the 3F corridor join them
    by a seam of no width, so the courtyard stays open."""
    a, b = LINK if connector else (LINK[0], LINK[0])
    return [
        [0, NORTH[0]], [L, NORTH[0]], [L, NORTH[1]], [b, NORTH[1]], [b, SOUTH[0]], [L, SOUTH[0]],
        [L, SOUTH[1]], [0, SOUTH[1]], [0, SOUTH[0]], [a, SOUTH[0]], [a, NORTH[1]], [0, NORTH[1]],
    ]


def traced(spaces, cell=0.2, close=0.6):
    """The outline of what the spaces cover: the signs' white margins are
    paper, not floor. Gaps narrower than `close` between neighbouring
    spaces are bridged; separate wings are joined by a seam of no width."""
    import math
    xs = [v for sp in spaces for v in (sp["rect"][0], sp["rect"][0] + sp["rect"][2])]
    ys = [v for sp in spaces for v in (sp["rect"][1], sp["rect"][1] + sp["rect"][3])]
    x0, y0 = min(xs) - 1, min(ys) - 1
    nx, ny = int((max(xs) + 1 - x0) / cell) + 1, int((max(ys) + 1 - y0) / cell) + 1
    grid = [[False] * nx for _ in range(ny)]
    for sp in spaces:
        x, y, w, h = sp["rect"]
        for j in range(int((y - y0) / cell + .5), int((y + h - y0) / cell + .5)):
            for i in range(int((x - x0) / cell + .5), int((x + w - x0) / cell + .5)):
                grid[j][i] = True
    r = math.ceil(close / cell / 2)

    def morph(g, grow):
        out = [[False] * nx for _ in range(ny)]
        for j in range(ny):
            for i in range(nx):
                window = (g[jj][ii] for jj in range(max(0, j - r), min(ny, j + r + 1))
                          for ii in range(max(0, i - r), min(nx, i + r + 1)))
                out[j][i] = any(window) if grow else all(window)
        return out

    grid = morph(morph(grid, True), False)
    # Boundary edges, each running with the covered cell on its left.
    edges = {}
    for j in range(ny):
        for i in range(nx):
            if not grid[j][i]:
                continue
            if j == 0 or not grid[j - 1][i]:
                edges[(i + 1, j)] = (i, j)
            if j == ny - 1 or not grid[j + 1][i]:
                edges[(i, j + 1)] = (i + 1, j + 1)
            if i == 0 or not grid[j][i - 1]:
                edges[(i, j)] = (i, j + 1)
            if i == nx - 1 or not grid[j][i + 1]:
                edges[(i + 1, j + 1)] = (i + 1, j)
    loops = []
    while edges:
        start, nxt = edges.popitem()
        loop = [start]
        while nxt != start:
            loop.append(nxt)
            nxt = edges.pop(nxt)
        # Keep corners only.
        pts = [p for k, p in enumerate(loop)
               if (p[0] - loop[k - 1][0], p[1] - loop[k - 1][1]) !=
               (loop[(k + 1) % len(loop)][0] - p[0], loop[(k + 1) % len(loop)][1] - p[1])]
        area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
        if area < 0:  # outer rings run this way round; holes the other
            loops.append([[round(x0 + i * cell, 2), round(y0 + j * cell, 2)] for i, j in pts])
    loops.sort(key=lambda l: min(p[1] for p in l))
    shape = loops[0]
    for ring in loops[1:]:
        # Seam from the nearest corners.
        a, b = min(((a, b) for a in range(len(shape)) for b in range(len(ring))),
                   key=lambda ab: (shape[ab[0]][0] - ring[ab[1]][0]) ** 2 + (shape[ab[0]][1] - ring[ab[1]][1]) ** 2)
        shape = shape[:a + 1] + ring[b:] + ring[:b + 1] + shape[a:]
    return shape


def to_admin(y):
    return {"to": "xingzheng", "name": "行政大樓", "at": [L, y], "toward": [1, 0]}


def floor_1f():
    s = Wing(1745, 625, 430, 655, SOUTH)
    n = Wing(1770, 610, 1015, 1265, NORTH)
    spaces = [
        s.rect("corridor", (625, 430, 865, 655)),
        s.rect("corridor", (865, 600, 1445, 655)),
        s.rect("corridor", (1360, 430, 1445, 600)),
        s.rect("stairs", (835, 550, 862, 600)),
        s.room((865, 445, 1030, 600), 103),
        s.room((1030, 445, 1185, 600), 102),
        s.rect("restroom", (1185, 445, 1245, 590), name="女廁"),
        s.rect("restroom", (1250, 445, 1325, 555), name="男廁"),
        s.rect("elevator", (1250, 555, 1290, 595)),
        s.rect("stairs", (1325, 445, 1360, 590)),
        s.room((1445, 440, 1715, 645), 101),
        n.rect("corridor", (610, 1015, 850, 1265)),
        n.rect("corridor", (850, 1015, 1770, 1080)),
        n.rect("corridor", (1620, 1080, 1770, 1265)),
        n.rect("stairs", (740, 1075, 778, 1220)),
        n.rect("elevator", (895, 1080, 940, 1110)),
        n.rect("restroom", (850, 1110, 945, 1175), name="男廁"),
        n.rect("restroom", (850, 1175, 945, 1255), name="女廁"),
        n.rect("stairs", (945, 1080, 1020, 1190)),
        n.rect("room", (945, 1190, 1020, 1240), name="儲藏室"),
        n.room((1020, 1080, 1195, 1240), 104),
        n.room((1195, 1080, 1370, 1240), 105),
        n.room((1370, 1080, 1555, 1240), 106),
        n.rect("stairs", (1555, 1100, 1620, 1250)),
    ]
    return {"id": "1F", "outline": outline(), "spaces": spaces,
            "links": [to_admin(46.0), to_admin(7.0)]}


def floor_2f():
    s = Wing(1815, 650, 340, 590, SOUTH)
    n = Wing(1750, 650, 950, 1215, NORTH)
    spaces = [
        s.rect("corridor", (650, 515, 1525, 590)),
        s.rect("corridor", (1440, 340, 1525, 515)),
        s.rect("stairs", (855, 415, 920, 515)),
        s.room((920, 355, 1095, 515), 203),
        s.room((1095, 355, 1255, 515), 202),
        s.rect("restroom", (1255, 355, 1330, 490), name="女廁"),
        s.rect("restroom", (1330, 355, 1410, 475), name="男廁"),
        s.rect("elevator", (1345, 475, 1400, 515)),
        s.rect("stairs", (1410, 355, 1440, 515)),
        s.room((1525, 355, 1800, 575), 201),
        n.rect("corridor", (650, 950, 1750, 1010)),
        n.rect("stairs", (790, 1010, 860, 1175)),
        n.rect("elevator", (950, 1005, 1000, 1045)),
        n.rect("restroom", (905, 1045, 1010, 1110), name="男廁"),
        n.rect("restroom", (905, 1110, 1010, 1185), name="女廁"),
        n.room((1015, 1010, 1270, 1175), 204),
        n.room((1270, 1010, 1450, 1175), 205),
        n.room((1450, 1010, 1645, 1175), 206),
        n.rect("stairs", (1645, 1010, 1745, 1180)),
    ]
    # East of the classrooms only the corridors carry on to 行政大樓.
    se, ne = s.x(905), n.x(780)
    sc, nc = sorted((s.y(515), s.y(590))), sorted((n.y(950), n.y(1010)))
    shape = [
        [0, NORTH[0]], [ne, NORTH[0]], [ne, nc[0]], [L, nc[0]], [L, nc[1]], [ne, nc[1]], [ne, NORTH[1]],
        [LINK[0], NORTH[1]], [LINK[0], SOUTH[0]],
        [se, SOUTH[0]], [se, sc[0]], [L, sc[0]], [L, sc[1]], [se, sc[1]], [se, SOUTH[1]],
        [0, SOUTH[1]], [0, SOUTH[0]], [LINK[0], SOUTH[0]], [LINK[0], NORTH[1]], [0, NORTH[1]],
    ]
    return {"id": "2F", "outline": shape, "spaces": spaces,
            "links": [to_admin(round(sum(sc) / 2, 2)), to_admin(round(sum(nc) / 2, 2))]}


def floor_3f():
    s = Wing(1735, 740, 300, 555, SOUTH)
    n = Wing(1660, 680, 905, 1195, NORTH)
    spaces = [
        s.rect("corridor", (765, 490, 1445, 555)),
        s.rect("stairs", (765, 405, 830, 490)),
        s.room((830, 330, 915, 490), "303-1"),
        s.room((915, 330, 1000, 490), 303),
        s.room((1000, 330, 1170, 490), 302),
        s.rect("restroom", (1170, 335, 1245, 455), name="女廁"),
        s.rect("restroom", (1250, 335, 1310, 455), name="男廁"),
        s.rect("elevator", (1245, 455, 1295, 490)),
        s.rect("stairs", (1310, 300, 1445, 490)),
        s.room((1445, 330, 1715, 545), 301),
        # The corridor joining the wings.
        {"kind": "corridor", "rect": [LINK[0], NORTH[1], round(LINK[1] - LINK[0], 2), SOUTH[0] - NORTH[1]]},
        n.rect("corridor", (735, 905, 1610, 975)),
        n.rect("stairs", (740, 975, 780, 1150)),
        n.rect("elevator", (865, 975, 905, 1010)),
        n.rect("restroom", (820, 1010, 915, 1080), name="男廁"),
        n.rect("restroom", (820, 1080, 915, 1150), name="女廁"),
        n.room((920, 975, 1175, 1140), 304),
        n.room((1175, 975, 1355, 1140), 305),
        n.room((1355, 975, 1545, 1140), 306),
        n.rect("stairs", (1550, 995, 1610, 1150)),
    ]
    return {"id": "3F", "outline": outline(connector=True), "spaces": spaces}


def floor_4f():
    s = Wing(1680, 660, 330, 600, SOUTH)
    n = Wing(1580, 680, 955, 1225, NORTH)
    spaces = [
        s.rect("corridor", (685, 535, 1365, 600)),
        s.rect("corridor", (1275, 335, 1365, 535)),
        s.rect("stairs", (685, 445, 745, 535)),
        s.room((750, 375, 920, 535), 403),
        s.room((920, 375, 1095, 535), 402),
        s.rect("restroom", (1095, 370, 1170, 520), name="女廁"),
        s.rect("restroom", (1175, 370, 1240, 490), name="男廁"),
        s.rect("elevator", (1180, 490, 1230, 525)),
        s.rect("stairs", (1240, 375, 1275, 520)),
        s.room((1365, 360, 1650, 575), 401),
        n.rect("corridor", (685, 955, 1570, 1015)),
        n.rect("stairs", (690, 1015, 728, 1170)),
        n.rect("elevator", (815, 1015, 865, 1045)),
        n.rect("restroom", (780, 1045, 875, 1110), name="男廁"),
        n.rect("restroom", (780, 1110, 875, 1190), name="女廁"),
        n.room((875, 1015, 1130, 1175), 404),
        n.room((1130, 1015, 1310, 1175), 405),
        n.room((1310, 1015, 1505, 1175), 406),
        n.rect("stairs", (1505, 1015, 1565, 1170)),
    ]
    return {"id": "4F", "outline": outline(), "spaces": spaces}


def tight(plan):
    plan["outline"] = traced(plan["spaces"])
    return plan


def main():
    building = {
        "id": "zonghe",
        "name": "綜合教學大樓",
        "unit": "m",
        "floors": [tight(f()) for f in (floor_1f, floor_2f, floor_3f, floor_4f)],
    }
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/zonghe.json", root / "mobile/assets/campus_map/zonghe.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
