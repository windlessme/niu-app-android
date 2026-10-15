#!/usr/bin/env python3
"""Generates app-content/campus-map/yuyan.json (語言中心).

Walls and proportions come from the accessibility map that hangs in the
building (外國語言教育中心無障礙地圖, 1F and 2F side by side); room names
and numbers from the floor guides (語言中心1樓／2樓平面圖), which split a
few of the map's rooms (廚房 off 國際學舍站, 茶水間 off the men's room).
Both are drawn north up: the offices line the east wall, the corridor runs
north–south with a wheelchair lift outside its north end, and the way out
is at its south end.

The photo of the map was taken at a slant, so each floor is squared off by
its four outer corners (the hidden north-west one found where the west and
north walls meet) into a 21.7 × 26.8 m box, the length of the
OpenStreetMap outline's walls, drawn square to the page. Each wall is
measured once, at one pixel on it, and every room is built from those
lines, so neighbours share their walls exactly.

1F is bigger than the OpenStreetMap outline, which follows 2F: 國際學舍站
and the kitchen reach north-west under the roof that 2F's map hatches.
Rooms keep the centre's own codes (LC101).
"""
import json
from pathlib import Path

UNIT = "外國語言教育中心"
ALIASES = ["語言中心", "語言教育中心"]
W, H = 21.7, 26.8  # the OpenStreetMap outline's south and east walls
LIFT = 3.5  # depth of the lift outside the north wall


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


class Sign:
    """One floor of the photographed map, pixels on the photo scaled to
    1600 px on its long side. The west wall (through two pixels) and the
    north wall (through two more, the second the north-east corner) meet
    at the north-west corner; with the south-east and south-west corners
    the four square the floor off into the W × H box."""

    def __init__(self, west, north, se, sw):
        nw = meet(*west, *north)
        a, b = [], []
        for (u, v), (x, y) in ((nw, (0, 0)), (north[1], (W, 0)), (se, (W, H)), (sw, (0, H))):
            a.append([u, v, 1, 0, 0, 0, -u * x, -v * x])
            b.append(x)
            a.append([0, 0, 0, u, v, 1, -u * y, -v * y])
            b.append(y)
        self.h = solve(a, b)

    def raw(self, u, v):
        h = self.h
        w = h[6] * u + h[7] * v + 1
        return (h[0] * u + h[1] * v + h[2]) / w, (h[3] * u + h[4] * v + h[5]) / w

    def x(self, u, v):
        """A wall running north–south, measured at one pixel on it."""
        return round(self.raw(u, v)[0], 2)

    def y(self, u, v):
        """A wall running east–west, measured at one pixel on it."""
        return round(self.raw(u, v)[1], 2)


def rect(kind, x0, y0, x1, y1, code=None, name=None, note=None):
    space = {"kind": kind, "rect": [x0, y0, round(x1 - x0, 2), round(y1 - y0, 2)]}
    if code:
        space["code"] = f"LC{code}"
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


def room(x0, y0, x1, y1, code=None, name=None, note=None):
    return rect("room", x0, y0, x1, y1, code, name, note)


def stack(x0, x1, ys, rooms):
    """Rooms one under the other between x0 and x1, split at ys."""
    return [room(x0, a, x1, b, code, name) for (code, name), a, b in zip(rooms, ys, ys[1:])]


def floor_1f():
    s = Sign(west=((256.7, 678.3), (278.3, 961.7)), north=((261.7, 280.7), (833.3, 295.0)),
             se=(828.3, 900.0), sw=(278.3, 961.7))
    xs_w = s.x(278.3, 553.3)  # 國際學舍站's west wall, set in from the men's room's
    store_w = s.x(363.3, 626.7)  # the storeroom's west wall, outside; the kitchen's east wall
    stair_w = s.x(450.0, 593.3)  # the accessible toilet's and the stairs' west wall
    men_e = s.x(466.7, 710.0)
    lc108_e = s.x(411.7, 866.7)
    hall_w = s.x(546.7, 700.0)
    hall_e = s.x(610.0, 493.3)  # LC105–LC103
    hall_e2 = s.x(630.0, 750.0)  # LC102 and LC101
    xs_s = s.y(316.7, 561.7)  # 國際學舍站's south wall
    toilet_s = s.y(500.0, 613.3)
    men_n = s.y(350.0, 675.0)
    men_s = s.y(350.0, 746.7)
    lc107_n = s.y(483.3, 820.0)
    east = [0, s.y(733.3, 431.7), s.y(733.3, 553.3), s.y(733.3, 676.7), s.y(733.3, 796.7), H]
    spaces = [
        rect("elevator", hall_w, -LIFT, hall_e, 0),
        rect("corridor", hall_w, 0, hall_e, east[3]),
        rect("corridor", hall_w, east[3], hall_e2, H),
        # The lobby in front of LC108 and LC107.
        rect("corridor", lc108_e, men_s, hall_w, lc107_n),
        room(xs_w, 0, store_w, xs_s, "111", "廚房"),
        room(store_w, 0, hall_w, xs_s, "106", "國際學舍站"),
        *stack(hall_e, W, east[:4], [("105", "悅讀角落"), ("104", "教學卓越計畫辦公室"), ("103", "電腦自學室")]),
        room(hall_e2, east[3], W, east[4], "102", "主任辦公室"),
        room(hall_e2, east[4], W, H, "101", "中心辦公室", note=UNIT),
        room(store_w, xs_s, stair_w, men_n, "109", "儲藏室"),
        rect("restroom", stair_w, xs_s, hall_w, toilet_s, name="無障礙廁所"),
        rect("stairs", stair_w, toilet_s, hall_w, men_n),
        rect("restroom", 0, men_n, men_e, men_s, name="男廁"),
        room(men_e, men_n, hall_w, men_s, "110", "茶水間"),
        room(0, men_s, lc108_e, H, "108", "研討室"),
        room(lc108_e, lc107_n, hall_w, H, "107", "英語聊天角落"),
    ]
    outline = [[xs_w, 0], [W, 0], [W, H], [0, H], [0, men_n], [store_w, men_n], [store_w, xs_s], [xs_w, xs_s]]
    return {"id": "1F", "outline": outline, "spaces": spaces, "unit": UNIT, "aliases": ALIASES}


def floor_2f():
    s = Sign(west=((958.3, 641.7), (964.6, 885.4)), north=((1181.3, 306.3), (1422.9, 311.7)),
             se=(1377.0, 841.7), sw=(964.6, 885.4))
    stair_w = s.x(1043.8, 560.0)
    tea_w = s.x(1102.1, 733.3)  # also LC209's and LC211's shared wall
    hall_w = s.x(1181.3, 366.7)
    hall_e = s.x(1235.0, 530.0)
    stair_n = s.y(1075.0, 525.0)
    ladies_n = s.y(1033.3, 641.7)
    ladies_s = s.y(1033.3, 704.2)
    tea_s = s.y(1137.5, 772.9)
    lc208_s = s.y(1075.0, 790.0)
    store_n = s.y(1129.2, 808.3)
    east = [0, *[s.y(1325.0, v) for v in (385.4, 464.6, 537.5, 641.7, 714.6, 785.4)], H]
    rooms = [("201", "兼任教師休息室"), ("202", "兼任教師休息室"), ("203", "教師研究室"), ("204", "會議室"),
             ("205", "教師研究室"), ("206", "教師研究室"), ("207", "教師研究室")]
    spaces = [
        rect("elevator", hall_w, -LIFT, hall_e, 0),
        rect("corridor", hall_w, 0, hall_e, H),
        rect("corridor", tea_w, tea_s, hall_w, store_n),
        *stack(hall_e, W, east, rooms),
        rect("stairs", stair_w, stair_n, hall_w, ladies_n),
        rect("restroom", 0, ladies_n, hall_w, ladies_s, name="女廁"),
        room(0, ladies_s, tea_w, lc208_s, "208", "教師研究室"),
        room(tea_w, ladies_s, hall_w, tea_s, "210", "茶水間"),
        room(0, lc208_s, tea_w, H, "209", "教師研究室"),
        room(tea_w, store_n, hall_w, H, "211", "儲藏室"),
    ]
    outline = [[hall_w, 0], [W, 0], [W, H], [0, H], [0, ladies_n], [stair_w, ladies_n], [stair_w, stair_n],
               [hall_w, stair_n]]
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
