#!/usr/bin/env python3
"""Generates app-content/campus-map/tongshi.json (通識教育中心).

Two floors, from two kinds of sign in the building. 「通識教育中心無障礙地圖」
draws both floors to scale, north up with the street (人行道, 學思林蔭大道)
to the south and the parking by the east road at the top right; its walls
give the geometry, drawn square and scaled to the OpenStreetMap outline's
39.4 m length. The directory signs on each floor (「求真樓一樓／二樓平面圖」)
are north up too, 求101 at the west end and the toilets, lift and stairs at
the east end on both floors, and give the room numbers and who is in each
room: they number the rooms 求101, 求102 … so that is the code. Where the
two disagree the directory wins: the room the accessibility map calls 茶水室
is 求107 兼任教師休息室 on 1F and 求209 教材準備室 on 2F.

The stairwell and the lift are one shaft each, drawn identically on both
floors at the east end. The outline's two southern bulges are 求101 (it
runs the full depth on the directory, beside the 花台 that fills the recess
between) and the stairwell with the entrance beside it; the rest of the
east bulge is the ramp outside. 2F has no west bulge: its corridor runs
along the whole south side.
"""
import json
from pathlib import Path

UNIT = "通識教育中心"
ALIASES = ["通識中心", "通識"]

# Wall lines in metres, east of the west wall. The walls the two floors
# share line up on the accessibility map (9.8, 15.9, 24.7, 30.8, 33.5), so
# both floors are built from one list. Measured on IMG_6036 (1600 px long
# side): 1F's outer walls run 382–1230 px across, 2F's 376–1252, both
# 39.4 m.
X0, A, B, C, D, E, F, G, H, S, X1 = 0, 6.8, 9.8, 15.9, 18.8, 21.8, 24.7, 30.8, 33.5, 34.4, 39.4
LIFT = 37.3  # the lift's west wall
# North to south: the outer north wall, the rooms' south wall, the
# corridor's south wall (the recess where the 花台 is), the outline's
# bulges. The map is to scale, 0.046 m a pixel down as well as across.
N, ROOMS, SOUTH = 0, 8.4, 11.1
WEST_BULGE, EAST_BULGE = 12.6, 13.0
LIFT_TOP = 5.8

# The stairwell and the lift are the same shafts on both floors. The stairs
# are a U-turn of two east–west flights, so the treads run north–south.
SHAFTS = [
    ("stairs", S, ROOMS, X1, EAST_BULGE),
    ("elevator", LIFT, LIFT_TOP, X1, ROOMS),
]


def rect(kind, x0, y0, x1, y1, code=None, name=None, note=None):
    space = {"kind": kind, "rect": [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)]}
    if code:
        space["code"] = f"求{code}"
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


def room(*box, code=None, name=None, note=None):
    return rect("room", *box, code=code, name=name, note=note)


def floor_1f():
    spaces = [
        *(rect(*shaft) for shaft in SHAFTS),
        rect("corridor", C, N, D, ROOMS),
        rect("corridor", B, ROOMS, H, SOUTH),
        # The entrance from the street, beside the stairs, and the lift lobby.
        rect("corridor", H, ROOMS, S, EAST_BULGE),
        rect("corridor", H, LIFT_TOP, LIFT, ROOMS),
        rect("restroom", H, N, X1, 4.2, name="女廁"),
        rect("restroom", H, 4.2, 36.0, LIFT_TOP, name="無障礙廁所"),
        rect("restroom", 36.0, 4.2, X1, LIFT_TOP, name="男廁"),
        room(X0, N, B, 3.8, name="中心主任辦公室", note=UNIT),
        # 求101 runs the full depth, out to the outline's west bulge.
        room(X0, 3.8, B, WEST_BULGE, code="101", name="通識教育中心辦公室"),
        room(B, N, C, 4.45, code="103", name="吳鳳珠老師"),
        room(B, 4.45, C, ROOMS, code="102", name="劉怡伶老師"),
        room(D, N, F, 4.45, code="104", name="徐明藤老師"),
        room(D, 4.45, F, ROOMS, code="105", name="楊淳凱老師"),
        room(F, N, G, ROOMS, code="106", name="會議室"),
        room(G, N, H, ROOMS, code="107", name="兼任教師休息室"),
    ]
    # The outline's east bulge west of the entrance hall is the ramp
    # outside, so it is left out.
    outline = [[X0, N], [X1, N], [X1, EAST_BULGE], [H, EAST_BULGE], [H, SOUTH],
               [B, SOUTH], [B, WEST_BULGE], [X0, WEST_BULGE]]
    return {"id": "1F", "outline": outline, "spaces": spaces}


def floor_2f():
    spaces = [
        *(rect(*shaft) for shaft in SHAFTS),
        rect("corridor", A, N, B, ROOMS),
        rect("corridor", E, N, F, ROOMS),
        rect("corridor", X0, ROOMS, S, SOUTH),
        rect("corridor", H, LIFT_TOP, LIFT, ROOMS),
        rect("restroom", H, N, X1, 3.4, name="女廁"),
        rect("restroom", H, 3.4, X1, LIFT_TOP, name="男廁"),
        room(X0, N, A, 4.2, code="202", name="張松年老師"),
        room(X0, 4.2, A, ROOMS, code="201", name="蔣忠慈老師"),
        room(B, N, C, 3.9, code="203", name="楊淳皓老師"),
        room(B, 3.9, C, ROOMS, code="204", name="許惠琪老師"),
        room(C, N, E, 3.9, code="206", name="錢芷萍老師"),
        room(C, 3.9, E, ROOMS, code="205", name="陳雀倩老師"),
        room(F, N, G, 3.8, code="207", name="邵維慶老師"),
        room(F, 3.8, G, ROOMS, code="208", name="討論室"),
        room(G, N, H, ROOMS, code="209", name="教材準備室"),
    ]
    outline = [[X0, N], [X1, N], [X1, EAST_BULGE], [S, EAST_BULGE], [S, SOUTH], [X0, SOUTH]]
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
