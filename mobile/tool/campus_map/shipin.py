#!/usr/bin/env python3
"""Generates app-content/campus-map/shipin.json (食品系實習工廠).

Measured from the 2F and 3F evacuation maps (食品科學系實習工廠), which hang
north up: the long side runs east–west like the 39 × 19 m OpenStreetMap
outline, the stair tower sticks out to the north, and the west end and the
east stair reach further south than the corridor between them. Drawn
axis-aligned on the OSM size; the 2F sign is drawn front-on and nearly to
scale, so its walls set the shared lines below.

3F is smaller than 2F: its sign puts the north stair at the floor's west
corner (on 2F it is 7.4 m in from the west wall), and its corridor wall and
east stair line up with 2F's only if the floor starts at the stair tower's
west wall, so 3F covers x ≥ 7.4 m and the west end is 2F's roof. The 2F west
stair only goes down; the east stair goes on up to 3F. A small lift is drawn
outside the south wall on 2F; the 3F sign has none.

There is no 1F sign. 1F repeats 2F's walls, stairs and lift, with its rooms
left unnamed. Rooms have no numbers on the signs, so they keep only names.
"""
import json
from pathlib import Path

W, D = 39.0, 19.1  # footprint, metres
CORE = 16.5  # the corridor's south wall, where the middle of the building ends
TOWER = (7.4, 14.4, -3.6)  # north stair tower: x0, x1, north face
ROW = 14.1  # corridor north wall
STAIR_E = 32.4  # east stair's west wall
LOBBY = 28.0  # the east stair lobby reaches the south wall from here
LIFT = (12.9, 15.3, 20.6)  # 2F/1F lift outside the south wall: x0, x1, south face
UNIT = "食品科學系"
ALIASES = ["食科系"]


def rect(kind, x0, y0, x1, y1, name=None):
    space = {"kind": kind, "rect": [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)]}
    if name:
        space["name"] = name
    return space


def poly(kind, points, name=None):
    space = {"kind": kind, "polygon": [[round(x, 2), round(y, 2)] for x, y in points]}
    if name:
        space["name"] = name
    return space


def tower():
    return rect("stairs", TOWER[0], TOWER[2], TOWER[1], 0)


def east_stair():
    return rect("stairs", STAIR_E, ROW, W, D)


# 1F and 2F share these walls.
WEST = 9.2  # 單操實驗室's east wall
WEST_STAIR = (4.5, 11.1)  # west stair, south of the 單操實驗室
RECESS = 15.3  # the lift lobby off the corridor ends here
STORE3 = (15.0, 8.2)  # 器材室(三): east wall, north wall
TOP_ROW = 4.5  # 烹飪教室 / 器材室(二) south wall
EAST_ROOMS = 31.1  # 器材室(一)(二) west wall
STORE1_S = 9.3  # 器材室(一) south wall
LOCKER_N = 11.8  # 置物間 north wall

LOW_OUTLINE = [
    [0, 0], [TOWER[0], 0], [TOWER[0], TOWER[2]], [TOWER[1], TOWER[2]], [TOWER[1], 0], [W, 0], [W, D],
    [LOBBY, D], [LOBBY, CORE], [RECESS, CORE], [RECESS, LIFT[2]], [LIFT[0], LIFT[2]], [LIFT[0], D], [0, D],
]


def low_floor(level, names):
    """1F/2F: names maps each room's key to its name (None leaves it unnamed)."""
    spaces = [
        tower(),
        east_stair(),
        rect("stairs", WEST_STAIR[0], ROW, WEST_STAIR[1], D),
        rect("elevator", LIFT[0], D, LIFT[1], LIFT[2]),
        poly("corridor", [
            (WEST_STAIR[1], ROW), (STAIR_E, ROW), (STAIR_E, D), (LOBBY, D), (LOBBY, CORE),
            (RECESS, CORE), (RECESS, D), (WEST_STAIR[1], D),
        ]),
        # The passage past 置物間 into the strip below 器材室(一).
        poly("corridor", [
            (EAST_ROOMS, STORE1_S), (W, STORE1_S), (W, LOCKER_N), (STAIR_E, LOCKER_N), (STAIR_E, ROW),
            (EAST_ROOMS, ROW),
        ]),
        rect("room", 0, 0, WEST, ROW, names["lab"]),
        rect("room", 0, ROW, WEST_STAIR[0], D, names["lab_store"]),
        rect("room", WEST, 0, EAST_ROOMS, TOP_ROW, names["cook"]),
        rect("room", EAST_ROOMS, 0, W, TOP_ROW, names["store2"]),
        rect("room", EAST_ROOMS, TOP_ROW, W, STORE1_S, names["store1"]),
        poly("room", [
            (WEST, TOP_ROW), (EAST_ROOMS, TOP_ROW), (EAST_ROOMS, ROW), (STORE3[0], ROW),
            (STORE3[0], STORE3[1]), (WEST, STORE3[1]),
        ], names["bake"]),
        rect("room", WEST, STORE3[1], STORE3[0], ROW, names["store3"]),
        rect("room", STAIR_E, LOCKER_N, W, ROW, names["locker"]),
    ]
    return {"id": level, "outline": LOW_OUTLINE, "spaces": spaces}


def floor_1f():
    return low_floor("1F", dict.fromkeys(
        ("lab", "lab_store", "cook", "store2", "store1", "bake", "store3", "locker")))


def floor_2f():
    floor = low_floor("2F", {
        "lab": "單操實驗室", "lab_store": "單操器材室", "cook": "烹飪教室", "store2": "器材室（二）",
        "store1": "器材室（一）", "bake": "烘焙教室", "store3": "器材室（三）", "locker": "置物間",
    })
    floor["unit"], floor["aliases"] = UNIT, ALIASES
    return floor


def floor_3f():
    x0 = TOWER[0]
    ferment = 13.0  # 發酵工廠(二) / (一)
    plant = 18.4  # 發酵工廠(一) / 生化製程工廠
    plant_s = 10.9  # 生化製程工廠's south wall
    hall = (25.6, 30.1)  # passage between 接待室 and 發酵倉庫
    wc = 9.3  # small 廁所 at the corridor's west end
    rooms_s = (10.5, 13.6)  # 廁所 / 器材室 south of the corridor
    outline = [
        [x0, TOWER[2]], [TOWER[1], TOWER[2]], [TOWER[1], 0], [W, 0], [W, D], [LOBBY, D], [LOBBY, CORE],
        [rooms_s[1], CORE], [rooms_s[1], D], [x0, D],
    ]
    spaces = [
        tower(),
        east_stair(),
        poly("corridor", [
            (wc, ROW), (STAIR_E, ROW), (STAIR_E, D), (LOBBY, D), (LOBBY, CORE), (wc, CORE),
        ]),
        rect("corridor", hall[0], plant_s, hall[1], ROW),
        rect("room", x0, 0, ferment, ROW, "發酵工廠（二）"),
        rect("room", ferment, 0, plant, ROW, "發酵工廠（一）"),
        rect("room", plant, 0, W, plant_s, "生化製程工廠"),
        rect("room", plant, plant_s, hall[0], ROW, "接待室"),
        rect("room", hall[1], plant_s, W, ROW, "發酵倉庫"),
        rect("restroom", x0, ROW, wc, CORE, "廁所"),
        rect("restroom", x0, CORE, rooms_s[0], D, "廁所"),
        rect("room", rooms_s[0], CORE, rooms_s[1], D, "器材室"),
    ]
    return {"id": "3F", "outline": outline, "spaces": spaces, "unit": UNIT, "aliases": ALIASES}


def main():
    building = {
        "id": "shipin",
        "name": "食品系實習工廠",
        "unit": "m",
        "floors": [f() for f in (floor_1f, floor_2f, floor_3f)],
    }
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/shipin.json", root / "mobile/assets/campus_map/shipin.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
