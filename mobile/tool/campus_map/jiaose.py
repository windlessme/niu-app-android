#!/usr/bin/env python3
"""Generates app-content/campus-map/jiaose.json (教穡大樓).

Measured from the evacuation maps on each floor, photographed and rectified
to a metre grid: x runs west→east along the long side (the core stairs are
on the west, the toilets on the east), y runs north→south... as drawn on the
signs; true north is not known yet. 1F–7F share one structural shell; 8F is
the roof floor with the conference hall.
"""
import json
import math
from pathlib import Path

W, D = 48.0, 37.3  # footprint, metres
TOP, C1, MID, C2, BOT = (0, 7.3), (7.3, 10), (10, 27), (27, 30), (30, D)
EAST = 39.6  # toilets and stairs east of here, top and bottom rows
VC = (40.1, 42.7)  # east corridor between the corridors
WEST_ROOMS = 8.2  # west rooms in the middle band end here
BLOCK = 23.5  # middle block starts here, ends at VC[0]


def rect(kind, x0, y0, x1, y1):
    return {"kind": kind, "rect": [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)]}


def poly(kind, points):
    return {"kind": kind, "polygon": [[round(x, 2), round(y, 2)] for x, y in points]}


def bulge(x, y0, y1, depth, lo=None, hi=None, steps=24):
    """Points of a wall from (x, y0) to (x, y1) bowing west by depth, clipped to lo..hi."""
    lo = y0 if lo is None else lo
    hi = y1 if hi is None else hi
    pts = []
    for i in range(steps + 1):
        y = lo + (hi - lo) * i / steps
        t = (y - y0) / (y1 - y0)
        pts.append((x - depth * math.sin(math.pi * t), y))
    return pts


def ellipse(cx, cy, rx, ry, a0, a1, steps=32):
    return [
        (cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / steps)),
         cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / steps)))
        for i in range(steps + 1)
    ]


def row(y, edges, kind="room"):
    return [rect(kind, a, y[0], b, y[1]) for a, b in zip(edges, edges[1:])]


STANDARD = [0, 7.9, 15.8, 23.7, 31.6, EAST]


def shell(top_edges=STANDARD, bottom_edges=STANDARD, west=True, core_rooms=()):
    """Spaces every typical floor shares."""
    spaces = [
        rect("corridor", 0, C1[0], W, C1[1]),
        rect("corridor", 0, C2[0], W, C2[1]),
        rect("corridor", WEST_ROOMS, MID[0], BLOCK, MID[1]),
        rect("corridor", VC[0], MID[0], VC[1], MID[1]),
        rect("corridor", EAST, 4.2, 41.2, TOP[1]),
        rect("corridor", EAST, BOT[0], 41.2, 32.9),
        rect("restroom", EAST, 0, W, 4.2),
        rect("stairs", 41.2, 4.2, 47.5, TOP[1]),
        rect("stairs", 41.2, BOT[0], 47.5, 32.9),
        rect("restroom", EAST, 32.9, W, D),
        rect("stairs", 11.3, 10.5, 16.5, 14.5),
        rect("elevator", 11.4, 15.0, 13.5, 16.8),
        rect("elevator", 13.5, 15.0, 15.6, 16.8),
        rect("elevator", 13.1, 19.6, 15.6, 22.0),
        rect("stairs", 11.3, 22.4, 16.5, 26.8),
        *row(TOP, top_edges),
        *row(BOT, bottom_edges),
        *core_rooms,
    ]
    return spaces


def notched():
    """Outline of floors with the open notch east of the east corridor."""
    return [[0, 0], [W, 0], [W, MID[0]], [VC[1], MID[0]], [VC[1], MID[1]], [W, MID[1]], [W, D], [0, D]]


def west_rooms(split=18.6):
    return [rect("room", 0, MID[0], WEST_ROOMS, split), rect("room", 0, split, WEST_ROOMS, MID[1])]


def floor_1f():
    facade = ellipse(W, 18.65, 3.4, 11.35, -90, 90)
    outline = [[0, 0], [W, 0], [W, TOP[1]], *[[x, y] for x, y in facade[1:-1]], [W, BOT[0]], [W, D], [0, D]]
    arc = bulge(23.8, MID[0], MID[1], 2.4)
    hall = [*arc, (31.6, MID[1]), (31.6, MID[0])]
    return {
        "id": "1F",
        "outline": outline,
        "spaces": [
            *shell(),
            rect("corridor", 0, MID[0], WEST_ROOMS, MID[1]),
            rect("corridor", VC[0], TOP[1], W, BOT[0]),
            poly("corridor", [(W, TOP[1]), *facade[1:-1], (W, BOT[0])]),
            rect("void", 0.4, 12.0, WEST_ROOMS, 24.8),
            rect("stairs", 3.3, 24.8, 5.6, MID[1]),
            poly("room", hall),
            rect("room", 31.6, MID[0], 40.1, 22.7),
            rect("room", 31.6, 22.7, 34.25, MID[1]),
            rect("room", 34.25, 22.7, 37.0, 24.75),
            rect("room", 37.0, 22.7, 40.1, 24.75),
            rect("restroom", 34.25, 24.75, 37.0, MID[1]),
        ],
    }


def floor_2f():
    arc = bulge(23.8, MID[0], MID[1], 2.5)
    return {
        "id": "2F",
        "outline": notched(),
        "spaces": [
            *shell(),
            rect("void", 0.4, MID[0], WEST_ROOMS, MID[1]),
            poly("room", [*arc, (31.6, MID[1]), (31.6, MID[0])]),
            rect("room", 31.6, MID[0], 40.1, 22.4),
            rect("room", 31.6, 22.4, 35.6, 25.6),
            rect("room", 35.6, 22.4, 40.1, MID[1]),
        ],
    }


def floor_3f():
    def band(lo, hi):
        return poly("room", [*bulge(23.8, MID[0], MID[1], 2.0, lo, hi), (31.6, hi), (31.6, lo)])

    return {
        "id": "3F",
        "outline": notched(),
        "spaces": [
            *shell(),
            *west_rooms(18.8),
            band(MID[0], 15.1),
            band(15.1, 22.5),
            band(22.5, MID[1]),
            rect("room", 31.6, MID[0], 40.1, 22.5),
            rect("room", 31.6, 22.5, 40.1, MID[1]),
        ],
    }


def floor_4f():
    return {
        "id": "4F",
        "outline": notched(),
        "spaces": [
            *shell(),
            *west_rooms(18.5),
            rect("room", BLOCK, MID[0], 31.6, 18.5),
            rect("room", BLOCK, 18.5, 31.6, MID[1]),
            rect("room", 31.6, MID[0], 40.1, 14.75),
            rect("room", 31.6, 14.75, 40.1, 18.5),
            rect("room", 31.6, 18.5, 40.1, 22.3),
            rect("room", 31.6, 22.3, 40.1, MID[1]),
        ],
    }


def floor_5f():
    return {
        "id": "5F",
        "outline": notched(),
        "spaces": [
            *shell(
                top_edges=[0, 8.4, 16.3, 21.5, 28.0, 33.0, 37.5, EAST],
                bottom_edges=[0, 16.3, 28.0, EAST],
                core_rooms=[rect("room", 16.6, 10.4, 21.0, 16.8), rect("room", 16.6, 20.6, 21.0, 26.8)],
            ),
            *west_rooms(18.7),
            rect("room", BLOCK, MID[0], 32.0, 14.8),
            rect("room", 32.0, MID[0], 40.1, 14.8),
            rect("room", BLOCK, 14.8, 32.0, 18.5),
            rect("room", 32.0, 14.8, 40.1, 18.5),
            rect("room", BLOCK, 18.5, 32.0, MID[1]),
            rect("room", 32.0, 18.5, 40.1, 22.0),
            rect("room", 32.0, 22.0, 40.1, MID[1]),
        ],
    }


def floor_6f():
    return {
        "id": "6F",
        "outline": notched(),
        "spaces": [
            *shell(
                top_edges=[0, 4.1],
                bottom_edges=[0, 4.5],
                core_rooms=[rect("room", 16.7, 10.4, 21.0, 14.3), rect("room", 16.7, 14.3, 21.0, 16.8)],
            ),
            # Top row, west to east.
            rect("room", 4.1, 0, 8.3, 3.3),
            rect("room", 4.1, 3.3, 8.3, TOP[1]),
            *row(TOP, [8.3, 16.0, 27.7, 33.7, EAST]),
            # West band.
            rect("room", 0, MID[0], WEST_ROOMS, 18.1),
            rect("room", 0, 18.1, WEST_ROOMS, 21.6),
            rect("room", 0, 21.6, WEST_ROOMS, MID[1]),
            # Middle block.
            rect("room", BLOCK, MID[0], 27.8, 14.75),
            rect("room", 27.8, MID[0], 31.7, 14.75),
            rect("room", 31.7, MID[0], 40.1, 14.75),
            rect("room", BLOCK, 14.75, 27.8, 17.9),
            rect("room", 27.8, 14.75, 31.7, 17.9),
            rect("room", 31.7, 14.75, 40.1, 18.5),
            rect("room", BLOCK, 17.9, 31.7, 22.0),
            rect("room", 31.7, 18.5, 40.1, 22.0),
            rect("room", BLOCK, 22.0, 31.7, MID[1]),
            rect("room", 31.7, 22.0, 40.1, MID[1]),
            # Bottom row, west to east.
            rect("room", 4.5, BOT[0], 8.3, 33.5),
            rect("room", 4.5, 33.5, 8.3, D),
            *row(BOT, [8.3, 12.25, 16.3, 24.3]),
            rect("room", 24.3, BOT[0], 26.3, 32.7),
            rect("room", 24.3, 32.7, 28.3, D),
            poly("room", [(28.3, BOT[0]), (EAST, BOT[0]), (EAST, 33.7), (33.3, 33.7), (33.3, D), (28.3, D)]),
            rect("room", 33.3, 33.7, 36.8, D),
            rect("room", 36.8, 33.7, EAST, D),
        ],
    }


def floor_7f():
    return {
        "id": "7F",
        "outline": notched(),
        "spaces": [
            *shell(
                top_edges=[0, 4.2, 8.3, 12.2, 16.1, 20.0, 23.8, 27.75, 31.7, 35.7, EAST],
                bottom_edges=[0, 4.5, 8.3, 12.25, 16.2, 20.1, 24.0, 27.9, 32.3, EAST],
                core_rooms=[
                    rect("room", 16.7, 10.5, 20.8, 13.8),
                    rect("room", 16.7, 13.8, 20.8, 16.4),
                    rect("room", 16.7, 21.0, 20.8, MID[1]),
                ],
            ),
            *west_rooms(18.9),
            rect("room", BLOCK, MID[0], 31.7, 22.9),
            rect("room", 31.7, MID[0], 40.1, 22.9),
            rect("room", BLOCK, 22.9, 31.7, MID[1]),
            rect("room", 31.7, 22.9, 40.1, MID[1]),
        ],
    }


def floor_8f():
    north, south = 3.8, 33.1
    hall_east = ellipse(31.8, (north + south) / 2, 10.7, (south - north) / 2, -90, 90)
    lounge = ellipse(9.95, 18.5, 11.25, 7.9, 90, 270)
    indoor = [
        (9.95, north), (31.8, north), *hall_east[1:-1], (31.8, south), (9.95, south),
        (9.95, 26.4), *lounge[1:-1], (9.95, 10.6),
    ]
    # 交誼廳 is split east–west at 802/803 by the line drawn on the sign.
    split = 22.2
    cut = 9.95 - 11.25 * math.sqrt(1 - ((split - 18.5) / 7.9) ** 2)
    north_part = [p for p in lounge if p[1] < split]  # west then north
    south_part = [p for p in lounge if p[1] > split]  # south then west
    return {
        "id": "8F",
        "outline": [[0, 0], [W, 0], [W, D], [0, D]],
        "spaces": [
            rect("terrace", 0, 0, W, D),
            poly("corridor", indoor),
            rect("stairs", 39.3, 5.2, W, 8.3),
            rect("stairs", 39.3, 30.0, W, 33.1),
            rect("room", 9.95, north, 16.4, 10.6),
            rect("room", 16.4, north, 22.7, 10.6),
            rect("stairs", 11.8, 10.6, 16.8, 14.75),
            rect("elevator", 11.8, 15.0, 14.1, 16.8),
            rect("elevator", 14.1, 15.0, 16.4, 16.8),
            rect("elevator", 13.7, 19.8, 16.2, 22.0),
            rect("stairs", 11.8, 23.0, 16.8, 26.6),
            rect("room", 22.7, 15.0, 25.0, 22.7),
            rect("room", 9.95, 26.6, 16.2, south),
            rect("restroom", 16.2, 26.6, 19.75, south),
            rect("restroom", 19.75, 26.6, 22.7, south),
            poly("room", [(26.8, north), (31.8, north), *hall_east[1:-1], (31.8, south), (26.8, south)]),
            poly("room", [(9.95, split), (cut, split), *north_part]),
            poly("room", [(9.95, split), *south_part, (cut, split)]),
        ],
    }


def main():
    building = {
        "id": "jiaose",
        "name": "教穡大樓",
        "unit": "m",
        "floors": [f() for f in (floor_1f, floor_2f, floor_3f, floor_4f, floor_5f, floor_6f, floor_7f, floor_8f)],
    }
    out = Path(__file__).resolve().parents[3] / "app-content" / "campus-map" / "jiaose.json"
    out.write_text(json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(out)


if __name__ == "__main__":
    main()
