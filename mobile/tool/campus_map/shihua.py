#!/usr/bin/env python3
"""Generates app-content/campus-map/shihua.json (時化學舍, the men's dorm).

Measured from the evacuation maps on each floor and the lobby's room
directory (國立宜蘭大學男生宿舍各樓平面圖), scaled to the 80 m OpenStreetMap
length. The signs are drawn with north on the left (北門 by A, 南門 by E),
so plans are laid out in the signs' own frame (u along the corridor from the
north end, v down the sign from the east) and turned north up at the end:
A and E wings point east, B, C and D west. The 1F sign hangs upside down.

1F follows the user's corrections to its sign: the C wing is closed, the
office by the stairs is now the kitchen, the south 會議室 is the entrance,
and the north 會議室 and side door are gone.
"""
import json
from pathlib import Path

L, H = 80.0, 42.6  # sign frame: u north→south, v east→west
TOP = (3.65, 16.9)  # A and E wing rooms
UP = (16.9, 20.2)  # toilets and showers on the east side of the corridor
HALL = (20.2, 22.6)
DOWN = (22.6, 26.1)
BOTTOM = (26.1, 39.2)  # B, C and D wing rooms
WINGS = {"A": 19.2, "E": 61.5, "B": 10.9, "C": 39.9, "D": 69.2}
FIRST = {"A": 1, "B": 9, "C": 17, "D": 25, "E": 33}


def turned(u0, v0, u1, v1):
    """Sign frame to metres east (x) and south (y)."""
    return H - v1, u0, H - v0, u1


def rect(kind, u0, v0, u1, v1, code=None, name=None):
    x0, y0, x1, y1 = turned(u0, v0, u1, v1)
    space = {"kind": kind, "rect": [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)]}
    if code:
        space["code"] = code
    if name:
        space["name"] = name
    return space


def wing(level, letter, closed=False):
    """Eight rooms either side of the wing corridor and the common room at
    the end. Odd numbers on the north side, counting out from the corridor."""
    c = WINGS[letter]
    east = letter in "AE"
    span = TOP if east else BOTTOM
    end = (0, TOP[0]) if east else (BOTTOM[1], H)
    if closed:
        name = f"{letter} 區（不開放）"
        return [rect("room", c - 7.3, span[0], c + 7.3, span[1], name=name),
                rect("room", c - 4.3, end[0], c + 4.3, end[1], name=name)]
    spaces = [
        rect("corridor", c - 1.2, span[0], c + 1.2, span[1]),
        rect("room", c - 4.3, end[0], c + 4.3, end[1], name=f"{level}{letter} 起居室"),
    ]
    step = (span[1] - span[0]) / 4
    for r in range(4):
        # r counts rooms out from the main corridor.
        v0 = span[1] - (r + 1) * step if east else span[0] + r * step
        n = FIRST[letter] + 2 * r
        spaces.append(rect("room", c - 7.3, v0, c - 1.2, v0 + step, f"{level}{letter}{n:02d}", "寢室"))
        spaces.append(rect("room", c + 1.2, v0, c + 7.3, v0 + step, f"{level}{letter}{n + 1:02d}", "寢室"))
    return spaces


def services(level, letter):
    """The wing's toilets north of its corridor and showers south of it."""
    c = WINGS[letter]
    v = UP if letter in "AE" else DOWN
    return [
        rect("corridor", c - 1.4, v[0], c + 1.4, v[1]),
        rect("restroom", c - 10.7, v[0], c - 1.4, v[1], name=f"{level}{letter} 廁所"),
        rect("restroom", c + 1.4, v[0], c + 10.7, v[1], name=f"{level}{letter} 浴室"),
    ]


def outline(extra=()):
    pts = [(0, UP[0])]
    for letter in "AE":
        c = WINGS[letter]
        pts += [(c - 7.3, UP[0]), (c - 7.3, TOP[0]), (c - 4.3, TOP[0]), (c - 4.3, 0),
                (c + 4.3, 0), (c + 4.3, TOP[0]), (c + 7.3, TOP[0]), (c + 7.3, UP[0])]
        if letter == "A":
            pts += [(36.7, UP[0]), (36.7, 14.8), (43.2, 14.8), (43.2, UP[0])]
    pts += list(extra) + [(L, UP[0]), (L, DOWN[1])]
    for letter in "DCB":
        c = WINGS[letter]
        pts += [(c + 7.3, DOWN[1]), (c + 7.3, BOTTOM[1]), (c + 4.3, BOTTOM[1]), (c + 4.3, H),
                (c - 4.3, H), (c - 4.3, BOTTOM[1]), (c - 7.3, BOTTOM[1]), (c - 7.3, DOWN[1])]
    pts += [(0, DOWN[1])]
    return [[round(H - v, 2), round(u, 2)] for u, v in pts]


def floor(level):
    first = level == 1
    spaces = [
        rect("corridor", 0, HALL[0], L, HALL[1]),
        rect("stairs", 0, 15.8, 3.6, HALL[0]),
        rect("stairs", 76.6, 15.2, L, HALL[0]),
        rect("stairs", 36.7, 14.8, 43.2, UP[1]),
        # Balconies either side of the stairs, and the two west of the corridor.
        rect("terrace", 43.2, UP[0], 51.1, UP[1], name="陽台"),
        rect("terrace", 21.3, DOWN[0], 29.5, DOWN[1], name="陽台"),
        rect("terrace", 50.8, DOWN[0], 59.0, DOWN[1], name="陽台"),
    ]
    if first:
        spaces += [
            rect("room", 29.6, UP[0], 36.7, UP[1], name="廚房"),
            rect("room", 4.6, UP[0], 7.8, UP[1], name="管制室"),
            rect("room", 72.4, UP[0], 76.4, UP[1], name="管制室"),
            rect("corridor", 72.1, 2.7, 76.6, UP[0]),
            rect("room", 72.4, 2.9, 76.4, 9.0, name="入口"),
        ]
    else:
        spaces.append(rect("terrace", 29.6, UP[0], 36.7, UP[1], name="陽台"))
    for letter in "AEBCD":
        closed = first and letter == "C"
        spaces += wing(level, letter, closed=closed)
        if not closed:
            spaces += services(level, letter)
        else:
            c = WINGS[letter]
            spaces += [rect("restroom", c - 10.7, DOWN[0], c - 1.4, DOWN[1], name=f"{level}C 廁所"),
                       rect("restroom", c + 1.4, DOWN[0], c + 10.7, DOWN[1], name=f"{level}C 浴室")]
    extra = [(72.1, UP[0]), (72.1, 2.7), (76.6, 2.7), (76.6, UP[0])] if first else ()
    plan = {"id": f"{level}F", "outline": outline(extra), "spaces": spaces}
    return plan


def main():
    building = {
        "id": "shihua",
        "name": "時化學舍",
        "unit": "m",
        "floors": [floor(n) for n in range(1, 6)],
    }
    for f in building["floors"]:
        codes = [s["code"] for s in f["spaces"] if "code" in s]
        assert len(codes) == len(set(codes)), (f["id"], codes)
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/shihua.json", root / "mobile/assets/campus_map/shihua.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
