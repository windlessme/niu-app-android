#!/usr/bin/env python3
"""Generates app-content/campus-map/yuyan.json (語言中心).

Two floors, each read off its floor guide (語言中心1樓平面圖, 2樓平面圖),
which hang north up: the rooms LC101–LC105 and LC201–LC207 line the east
wall, the way out is at the south end of the corridor, and the stairs and
toilets sit where the building narrows on its west side. Both photos were
taken at a slant, so each sign is first squared off by its four outer
corners (the hidden north-west one found where the west and north walls
meet) into the 21.7 × 26.8 m box of the OpenStreetMap outline.

The guides are drawn a little out of proportion: the stairwell, the corridor
and the wide south part start up to 1.5 m off where the outline steps. Each
floor is stretched piecewise between those lines so they land on the
outline's steps, then turned the 1.3° the outline is turned.

The outline is 2F's. 1F reaches further north-west, under the roof the 2F
guide hatches: the kitchen and 國際學舍站 (LC106).

Rooms keep the centre's own codes (LC101); the name on the sign is the
room's name. The 2F guide marks an exit 往三樓 on the stairs, but there are
no signs for a third floor. The accessibility map (外國語言教育中心無障礙地圖)
shows an older 1F layout and a lift outside the corridor's north end, which
the floor guides do not; neither is drawn.
"""
import json
from pathlib import Path

UNIT = "外國語言教育中心"
ALIASES = ["語言中心", "語言教育中心"]

# OpenStreetMap's outline (way 256119630), metres east and south of its
# bounding box's north-west corner: the wide south part, the stairwell
# step, and the narrow north part.
OSM = [[0, 13.2], [0.3, 27.3], [22.0, 26.8], [21.4, 0], [9.1, 0.3], [9.3, 8.2], [4.7, 8.3], [4.8, 13.1]]
SW, SE, NE = OSM[1], OSM[2], OSM[3]
W, H = 21.7, 26.8  # the outline's south and east walls


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


def meet(a, b, c, d):
    """Where the line through a and b crosses the line through c and d."""
    (x1, y1), (x2, y2), (x3, y3), (x4, y4) = a, b, c, d
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / ((x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4))
    return x1 + t * (x2 - x1), y1 + t * (y2 - y1)


def to_osm(x, y):
    """The squared-off box (x east, y south, 0..W × 0..H) onto the outline,
    which is turned slightly."""
    u, v = x / W, (H - y) / H
    return [round(SW[0] + u * (SE[0] - SW[0]) + v * (NE[0] - SE[0]), 2),
            round(SW[1] + u * (SE[1] - SW[1]) + v * (NE[1] - SE[1]), 2)]


def from_osm(p):
    ax, ay = (SE[0] - SW[0]) / W, (SE[1] - SW[1]) / W
    bx, by = (NE[0] - SE[0]) / H, (NE[1] - SE[1]) / H
    dx, dy = p[0] - SW[0], p[1] - SW[1]
    det = ax * by - ay * bx
    return (dx * by - dy * bx) / det, H - (ax * dy - ay * dx) / det


# The outline's steps in the squared-off box.
STEP_X = (from_osm(OSM[6])[0], from_osm(OSM[4])[0])  # stairwell's west wall, corridor's west wall
STEP_Y = (from_osm(OSM[6])[1], from_osm(OSM[0])[1])  # stairwell's north wall, wide part's north wall


def piecewise(knots, t):
    for (a0, b0), (a1, b1) in zip(knots, knots[1:]):
        if t <= a1 or (a1, b1) == knots[-1]:
            return b0 + (t - a0) * (b1 - b0) / (a1 - a0)


class Sign:
    """One photographed floor guide. Pixel points are on the photo scaled
    to 1600 px on its long side. The four outer corners square the sign off
    into the W × H box; `steps` are the sign's own stairwell wall, corridor
    wall, stairwell north wall and wide-part north wall in that box, which
    are stretched onto the outline's."""

    def __init__(self, nw, ne, se, sw):
        a, b = [], []
        for (u, v), (x, y) in ((nw, (0, 0)), (ne, (W, 0)), (se, (W, H)), (sw, (0, H))):
            a.append([u, v, 1, 0, 0, 0, -u * x, -v * x])
            b.append(x)
            a.append([0, 0, 0, u, v, 1, -u * y, -v * y])
            b.append(y)
        self.h = solve(a, b)
        self.kx = self.ky = None

    def raw(self, u, v):
        h = self.h
        w = h[6] * u + h[7] * v + 1
        return (h[0] * u + h[1] * v + h[2]) / w, (h[3] * u + h[4] * v + h[5]) / w

    def x(self, u, v):
        """A wall running north–south, measured at one pixel on it."""
        return self.raw(u, v)[0]

    def y(self, u, v):
        """A wall running east–west, measured at one pixel on it."""
        return self.raw(u, v)[1]

    def steps(self, x0, x1, y0, y1):
        self.kx = [(0, 0), (x0, STEP_X[0]), (x1, STEP_X[1]), (W, W)]
        self.ky = [(0, 0), (y0, STEP_Y[0]), (y1, STEP_Y[1]), (H, H)]

    def pt(self, x, y):
        return to_osm(piecewise(self.kx, x), piecewise(self.ky, y))

    def poly(self, kind, ps, code=None, name=None, note=None):
        space = {"kind": kind, "polygon": [self.pt(*p) for p in ps]}
        if code:
            space["code"] = f"LC{code}"
        if name:
            space["name"] = name
        if note:
            space["note"] = note
        return space

    def box(self, kind, x0, y0, x1, y1, code=None, name=None, note=None):
        return self.poly(kind, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], code, name, note)

    def room(self, x0, y0, x1, y1, code=None, name=None, note=None):
        return self.box("room", x0, y0, x1, y1, code, name, note)


def floor_1f():
    s = Sign(meet((215.7, 895.0), (171.4, 1405.7), (308.6, 391.4), (1014.3, 510.7)),
             (1014.3, 510.7), (1017.9, 1355.7), (171.4, 1405.7))
    kitchen_w = s.x(296.4, 564.3)
    kitchen_e = s.x(410.7, 578.6)
    store_w = s.x(391.4, 807.1)  # LC109's west wall, the outside wall
    stair_w = s.x(500.0, 778.6)  # the accessible toilet's and the stairs' west wall
    men_e = s.x(521.4, 971.4)
    lc108_e = s.x(410.7, 1242.9)
    hall_w = s.x(635.7, 850.0)
    hall_e = s.x(742.9, 850.0)  # LC104 and LC103
    hall_e2 = s.x(767.9, 1064.3)  # LC102 and LC101
    lc106_s = s.y(342.9, 715.7)  # the kitchen's and LC106's south wall
    lc105_s = s.y(828.6, 692.9)
    lc104_s = s.y(900.0, 815.7)
    toilet_s = s.y(571.4, 825.0)  # the accessible toilet, north of the stairs
    men_n = s.y(364.3, 907.1)
    lc103_s = s.y(878.6, 990.7)
    men_s = s.y(364.3, 1032.1)
    lc107_n = s.y(507.1, 1098.6)
    lc102_s = s.y(892.9, 1162.9)
    s.steps(store_w, hall_w, lc106_s, men_n)

    spaces = [
        s.box("corridor", hall_w, lc105_s, hall_e, lc103_s),
        s.box("corridor", hall_w, lc103_s, hall_e2, H),
        # The lobby in front of LC108 and LC107.
        s.box("corridor", lc108_e, men_s, hall_w, lc107_n),
        s.room(kitchen_w, 0, kitchen_e, lc106_s, "111", "廚房"),
        s.room(kitchen_e, 0, hall_w, lc106_s, "106", "國際學舍站"),
        s.room(hall_w, 0, W, lc105_s, "105", "悅讀角落"),
        s.room(hall_e, lc105_s, W, lc104_s, "104", "教學卓越計畫辦公室"),
        s.room(hall_e, lc104_s, W, lc103_s, "103", "電腦自學室"),
        s.room(hall_e2, lc103_s, W, lc102_s, "102", "主任辦公室"),
        s.room(hall_e2, lc102_s, W, H, "101", "中心辦公室", note=UNIT),
        s.room(store_w, lc106_s, stair_w, men_n, "109", "儲藏室"),
        s.box("restroom", stair_w, lc106_s, hall_w, toilet_s, name="無障礙廁所"),
        s.box("stairs", stair_w, toilet_s, hall_w, men_n),
        s.box("restroom", 0, men_n, men_e, men_s, name="男廁"),
        s.room(men_e, men_n, hall_w, men_s, "110", "茶水間"),
        s.room(0, men_s, lc108_e, H, "108", "研討室"),
        s.room(lc108_e, lc107_n, hall_w, H, "107", "英語聊天角落"),
    ]
    outline = [s.pt(*p) for p in ((kitchen_w, 0), (W, 0), (W, H), (0, H), (0, men_n), (store_w, men_n),
                                  (store_w, lc106_s), (kitchen_w, lc106_s))]
    return {"id": "1F", "outline": outline, "spaces": spaces, "unit": UNIT, "aliases": ALIASES}


def floor_2f():
    s = Sign(meet((232.1, 875.0), (215.7, 1240.7), (514.3, 464.3), (891.4, 402.9)),
             (891.4, 402.9), (970.0, 1314.3), (215.7, 1240.7))
    stair_w = s.x(337.1, 794.3)
    lobby_w = s.x(389.3, 1094.3)
    store_w = s.x(422.9, 1201.4)  # LC211, and LC209's east wall
    tea_w = s.x(425.0, 1022.9)
    hall_w = s.x(517.9, 594.3)
    hall_e = s.x(612.9, 737.1)
    stair_n = s.y(414.3, 717.9)
    ladies_n = s.y(378.6, 872.9)
    ladies_s = s.y(378.6, 965.7)
    lobby_n = s.y(407.1, 1048.6)
    tea_s = s.y(471.4, 1087.1)
    lc208_s = s.y(307.1, 1100.0)
    store_n = s.y(471.4, 1130.7)
    east = [s.y(757.1, 522.9), s.y(764.3, 624.3), s.y(771.4, 737.1), s.y(792.9, 898.6), s.y(800.0, 1030.7),
            s.y(807.1, 1165.7)]  # the walls between LC201 … LC207, north to south
    s.steps(stair_w, hall_w, stair_n, ladies_n)

    rooms = [("201", "兼任教師休息室"), ("202", "兼任教師休息室"), ("203", "教師研究室"), ("204", "會議室"),
             ("205", "教師研究室"), ("206", "教師研究室"), ("207", "教師研究室")]
    walls = [0, *east, H]
    spaces = [
        s.box("corridor", hall_w, 0, hall_e, H),
        s.poly("corridor", [(lobby_w, lobby_n), (tea_w, lobby_n), (tea_w, tea_s), (hall_w, tea_s), (hall_w, store_n),
                            (lobby_w, store_n)]),
        *[s.room(hall_e, y0, W, y1, code, name) for (code, name), y0, y1 in zip(rooms, walls, walls[1:])],
        s.box("stairs", stair_w, stair_n, hall_w, ladies_n),
        s.box("restroom", 0, ladies_n, hall_w, ladies_s, name="女廁"),
        s.poly("room", [(0, ladies_s), (tea_w, ladies_s), (tea_w, lobby_n), (lobby_w, lobby_n), (lobby_w, lc208_s),
                        (0, lc208_s)], "208", "教師研究室"),
        s.room(tea_w, ladies_s, hall_w, tea_s, "210", "茶水間"),
        s.poly("room", [(0, lc208_s), (lobby_w, lc208_s), (lobby_w, store_n), (store_w, store_n), (store_w, H),
                        (0, H)], "209", "教師研究室"),
        s.room(store_w, store_n, hall_w, H, "211", "儲藏室"),
    ]
    outline = [s.pt(*p) for p in ((hall_w, 0), (W, 0), (W, H), (0, H), (0, ladies_n), (stair_w, ladies_n),
                                  (stair_w, stair_n), (hall_w, stair_n))]
    return {"id": "2F", "outline": outline, "spaces": spaces, "unit": UNIT, "aliases": ALIASES}


def main():
    building = {"id": "yuyan", "name": "語言中心", "unit": "m", "floors": [floor_1f(), floor_2f()]}
    for floor in building["floors"]:
        codes = [s["code"] for s in floor["spaces"] if "code" in s]
        assert len(codes) == len(set(codes)), (floor["id"], codes)
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/yuyan.json", root / "mobile/assets/campus_map/yuyan.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
