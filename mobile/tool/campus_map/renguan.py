#!/usr/bin/env python3
"""Generates app-content/campus-map/renguan.json (人文管理學院及外文系).

Sources: the building's directory board (人文及管理學院各樓層平面配置圖,
/root/大樓平面圖/人文管理學院及外文系/IMG_6117–6120), one panel a floor,
all north up: the lift, toilets and the north-east stairs along the north
side, the 大門 and the south-west stairs on the south. There are panels
for 1F–4F only.

The 1F panel draws the whole footprint, the round-ended 103 階梯教室 included,
and is close to the OpenStreetMap outline's 34 × 25 m, so it is read at one
scale (34 m from the hall's west tip to the east wall, 25 m from the lift's
north wall to the foot of the south-west stairs). The 2F–4F panels fill
their frames with a plain rectangle; read as 34 × 25 m they put the lift,
both stairs and the courtyard's west wall 1–2 m west of where 1F has them.
Squeezed to 0.9 and set 3.4 m east (`X`), they all land on 1F's, and the
hall's east wall becomes the courtyard's: the upper floors stop short of the
hall's rounded west end, which stands out on its own. The upper panels are
measured on photos rectified by their frames' corners and agree within a
few centimetres, so they share one set of wall lines; the shafts are the
same shapes on every floor. The stairs are drawn at 45°, as they are built.

OpenStreetMap rounds the west side all the way up, while every upper panel
has square rooms there; the panels win.

Room numbers lead the names (as in the library and 學生活動中心): the
directory numbers the rooms plainly (101, 205). The school's system codes
only five of them (user, 2026-10-19), each its own way; those go in `aka`,
so timetables find the room and the map keeps the sign's number. 402 is the
room east of 401, the one the 4F panel leaves unnumbered.
"""
import json
import math
from pathlib import Path

DEPT = "外國語文學系"
DEPT_ALIASES = ["外文系"]
COLLEGE = "人文及管理學院"
COLLEGE_ALIASES = ["人管院"]

# Sign number → the school's classroom code.
CODES = {"101": "語101", "102": "語102", "103": "人管階梯教室", "308": "人文308", "402": "人文402"}


def X(x):
    """An upper-floor panel's metres east of its west wall, to 1F's; the
    east wall (34) stays put."""
    return round(3.4 + 0.9 * x, 2)


# Shafts, the same on every floor (1F's metres).
LIFT = (22.5, 0, 25.0, 1.8)
NE_STAIRS = [[25.8, 4.0], [29.0, 1.0], [30.0, 2.9], [26.8, 6.0]]
SW_STAIRS = [[10.15, 23.6], [12.09, 21.45], [13.66, 23.1], [11.68, 25.0]]


def on_ne_stairs(*, x=None, y=None):
    """The point on the line of the north-east stairs' south-east side; the
    rooms beside them are cut along it."""
    (x0, y0), (x1, y1) = NE_STAIRS[3], NE_STAIRS[2]
    slope = (y1 - y0) / (x1 - x0)
    if x is not None:
        return [x, round(y0 + slope * (x - x0), 2)]
    return [round(x0 + (y - y0) / slope, 2), y]


def box(kind, x0, y0, x1, y1, name=None, note=None):
    space = {"kind": kind, "rect": [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)]}
    return labelled(space, name, note)


def poly(kind, points, name=None, note=None):
    return labelled({"kind": kind, "polygon": [[round(x, 2), round(y, 2)] for x, y in points]}, name, note)


def labelled(space, name, note):
    if name:
        space["name"] = name
        if code := CODES.get(name.split()[0]):
            space["aka"] = [code]
    if note:
        space["note"] = note
    return space


def shafts():
    return [box("elevator", *LIFT), poly("stairs", NE_STAIRS), poly("stairs", SW_STAIRS)]


def hall_arc():
    """103's curved west wall: the circle through its two ends that touches
    the building's west tip (x = 0)."""
    (ax, ay), (bx, by) = (8.75, 2.0), SW_STAIRS[0]
    # Centre (r, cy) with radius r: both ends at distance r.
    # (ax - r)^2 + (ay - cy)^2 = r^2, the same for b; solve for cy, then r.
    lo, hi = 0.0, 25.0
    for _ in range(80):
        cy = (lo + hi) / 2
        ra = (ax * ax + (ay - cy) ** 2) / (2 * ax)
        rb = (bx * bx + (by - cy) ** 2) / (2 * bx)
        lo, hi = (lo, cy) if ra > rb else (cy, hi)
    r = (ax * ax + (ay - cy) ** 2) / (2 * ax)
    start = math.atan2(ay - cy, ax - r)
    # North end to south end the long way round, through the west tip.
    end = math.atan2(by - cy, bx - r) - 2 * math.pi
    steps = 16
    return [[r + r * math.cos(start + (end - start) * i / steps),
             cy + r * math.sin(start + (end - start) * i / steps)] for i in range(steps + 1)]


def floor_1f():
    arc = hall_arc()
    hall = arc + [[12.09, 21.45], [14.1, 19.0], [14.1, 7.75], [12.25, 6.75], [8.75, 4.0]]
    spaces = [
        *shafts(),
        poly("room", hall, name="103 階梯教室"),
        # The women's toilets' west end follows the hall's slanted wall.
        poly("restroom", [[10.5, 2.0], [18.9, 2.0], [18.9, 6.75], [12.25, 6.75], [10.5, 5.37]], name="女廁"),
        box("restroom", 18.9, 2.0, 22.25, 6.75, name="男廁"),
        poly("terrace", [[14.1, 9.0], [24.1, 9.0], [24.9, 10.9], [24.9, 19.5], [19.1, 19.5],
                         [17.0, 17.25], [14.1, 17.25]], name="中庭"),
        poly("room", [on_ne_stairs(x=24.9), on_ne_stairs(y=2.5), [34, 2.5], [34, 15.1], [24.9, 15.1]],
             name="102 外國語文學系專業教室（二）"),
        poly("room", [[24.9, 15.1], [34, 15.1], [34, 22.9], [23.75, 22.9], [23.75, 21.3], [24.9, 21.3]],
             name="101 外國語文學系專業教室（一）"),
    ]
    # Round the hall's end, past the stairs and the south wall, up the east
    # side, round the stairs and the lift, and back along the north wall.
    outline = arc + [SW_STAIRS[3], SW_STAIRS[2], [13.66, 22.9], [34, 22.9], [34, 2.5], on_ne_stairs(y=2.5),
                     NE_STAIRS[2], NE_STAIRS[1], NE_STAIRS[0], [25.0, 1.8], [25.0, 0], [22.5, 0], [22.5, 2.0]]
    return {"id": "1F", "outline": rounded(outline), "spaces": spaces, "unit": DEPT, "aliases": DEPT_ALIASES}


def rounded(points):
    return [[round(x, 2), round(y, 2)] for x, y in points]


# Upper floors' wall lines, panel metres east (x) and 1F metres south (y).
WEST, WEST_ROOMS, MIDDLE, YARD_W, YARD_E, EAST = 0, 4.45, 6.8, 11.9, 22.85, 25.75
TOILETS, SPLIT, TOILETS_E = 11.9, 16.0, 20.4
NORTH_ROOMS, NORTH_ROOMS_S = 1.8, 5.4
YARD_N, YARD_S, SOUTH = 7.45, 20.4, 23.1


def upper_box(kind, x0, y0, x1, y1, name=None, note=None):
    return box(kind, X(x0), y0, X(x1), y1, name, note)


def east_block(rows):
    """The east rooms, north to south: (south wall, name, note); the first
    is cut along the stairs."""
    spaces, top = [], 3.8
    for i, (south, name, note) in enumerate(rows):
        if i == 0:
            spaces.append(poly("room", [on_ne_stairs(x=X(EAST)), on_ne_stairs(y=top), [34, top], [34, south],
                                        [X(EAST), south]], name, note))
        else:
            spaces.append(upper_box("room", EAST, top, 34, south, name, note))
        top = south
    return spaces


def south_west(name, note=None):
    """The room cut by the south-west stairs' slant, in the panel's metres."""
    return poly("room", [[X(0), 16.6], [X(7.7), 16.6], [X(9.5), 19.2], [X(10.2), 20.95], [X(0), 20.95]], name, note)


def toilets():
    return [
        upper_box("restroom", TOILETS, NORTH_ROOMS, SPLIT, NORTH_ROOMS_S, name="女廁"),
        upper_box("restroom", SPLIT, NORTH_ROOMS, TOILETS_E, NORTH_ROOMS_S, name="男廁"),
    ]


def upper(fid, spaces, unit, aliases):
    outline = [[X(WEST), 0], [34, 0], [34, 25], [X(WEST), 25]]
    for s in spaces:
        if "rect" in s:
            x, y, w, h = s["rect"]
            assert x >= X(WEST) - .01 and x + w <= 34.01, (fid, s)
    return {"id": fid, "outline": outline, "spaces": [*shafts(), *spaces], "unit": unit, "aliases": aliases}


def floor_2f():
    return upper("2F", [
        upper_box("room", WEST, NORTH_ROOMS, TOILETS, NORTH_ROOMS_S, name="205 系圖書室、討論室", note=DEPT),
        *toilets(),
        upper_box("room", WEST, NORTH_ROOMS_S, WEST_ROOMS, 9.05, name="206 傅雋老師"),
        upper_box("room", WEST, 9.05, WEST_ROOMS, 12.95, name="208 游依琳老師"),
        upper_box("room", WEST, 12.95, WEST_ROOMS, 16.6, name="210 蕭政華老師"),
        south_west("211 張雅玲老師"),
        upper_box("room", MIDDLE, YARD_N, YARD_W, 10.8, name="207"),
        upper_box("room", MIDDLE, 10.8, YARD_W, 14.0, name="209 儲藏室"),
        upper_box("void", YARD_W, YARD_N, YARD_E, YARD_S, name="中庭"),
        *east_block([
            (7.3, "204 高珮文老師", None),
            (11.8, "203 賴軍維老師", None),
            (16.1, "202 外國語文學系主任辦公室", DEPT),
            (SOUTH, "201 外國語文學系辦公室", DEPT),
        ]),
    ], DEPT, DEPT_ALIASES)


def floor_3f():
    return upper("3F", [
        upper_box("room", WEST, NORTH_ROOMS, 6.25, NORTH_ROOMS_S, name="306 儲藏室"),
        upper_box("room", 6.25, NORTH_ROOMS, TOILETS, NORTH_ROOMS_S, name="305 課業輔導室"),
        *toilets(),
        upper_box("room", WEST, NORTH_ROOMS_S, WEST_ROOMS, 12.6, name="307 多媒體室"),
        upper_box("room", WEST, 12.6, WEST_ROOMS, 16.6, name="309 兼任老師休息室"),
        south_west("310 系學會辦公室", DEPT),
        upper_box("room", MIDDLE, YARD_N, YARD_W, 14.0, name="308 外國語文學系會議室", note=DEPT),
        upper_box("void", YARD_W, YARD_N, YARD_E, YARD_S, name="中庭"),
        *east_block([
            (7.3, "304 張智欽老師", None),
            (11.8, "303 助理院長室", COLLEGE),
            (16.1, "302 人文及管理學院辦公室", COLLEGE),
            (SOUTH, "301 院長辦公室", COLLEGE),
        ]),
    ], COLLEGE, COLLEGE_ALIASES)


def floor_4f():
    return upper("4F", [
        upper_box("room", WEST, NORTH_ROOMS, MIDDLE, NORTH_ROOMS_S, name="406 人文及管理學院儲藏室", note=COLLEGE),
        upper_box("room", MIDDLE, NORTH_ROOMS, TOILETS, NORTH_ROOMS_S, name="405"),
        *toilets(),
        upper_box("room", WEST, NORTH_ROOMS_S, WEST_ROOMS, 9.05, name="407 研究生討論室"),
        upper_box("room", WEST, 9.05, WEST_ROOMS, 12.95, name="409 研究生研究室（一）"),
        upper_box("room", WEST, 12.95, WEST_ROOMS, 16.6, name="411 胡迪老師"),
        south_west("412 張慧老師"),
        upper_box("room", MIDDLE, YARD_N, YARD_W, 10.8, name="408 研究生研究室（二）"),
        upper_box("room", MIDDLE, 10.8, YARD_W, 14.0, name="410"),
        # 400 roofs over the courtyard's south end on this floor.
        upper_box("void", YARD_W, YARD_N, YARD_E, 16.2, name="中庭"),
        upper_box("room", 13.8, 16.2, YARD_E, SOUTH, name="400 外國語文學系教學助理工作室", note=DEPT),
        *east_block([
            (7.3, "404 錄音室（二）", None),
            (16.1, "403 人文及管理學院會議室", COLLEGE),
        ]),
        upper_box("room", EAST, 16.1, 29.95, SOUTH, name="401 錄音室（一）"),
        upper_box("room", 29.95, 16.1, 34, SOUTH, name="402"),
    ], DEPT, DEPT_ALIASES)


def main():
    building = {
        "id": "renguan",
        "name": "人文管理學院及外文系",
        "unit": "m",
        "floors": [floor_1f(), floor_2f(), floor_3f(), floor_4f()],
    }
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/renguan.json", root / "mobile/assets/campus_map/renguan.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
