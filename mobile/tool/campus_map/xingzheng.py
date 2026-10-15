#!/usr/bin/env python3
"""Generates app-content/campus-map/xingzheng.json (行政大樓).

Measured from the floor plan on each floor's stair landing (1F–5F). The signs
are drawn east up: the main entrance (正門入口) at the top of the 1F sign is
on the east side, the left wing is north, the right wing south, and the
courtyard (中庭) at the bottom opens to the west. North up, the building is a
C open to the west, with a stair in each inner corner of the courtyard.

The plan is drawn square, 31.8 × 52.3 m: OpenStreetMap's outline with its
slight tilt taken out. Its notch gives the lines every floor shares: the
wings' inner walls, the stairs' sides and the courtyard's east edge. The
signs aren't to scale, so each photo is squared up by its four corners (a
projective map, which also takes out the camera's slant), then stretched
piecewise between those shared lines. Each floor's walls are read off once
as lists of lines, and rooms are built from them.

On 3F–5F the north wing stops short of the west wall (all three signs draw
the courtyard running past its end), so those floors' outlines are cut
there. 2F has an open void over the entrance lobby.

Rooms are the administrative units named on the signs and the lift
directory; where a sign draws two units in one box with no wall between
(301 會議室／校友會, 事務組／採購組, 學術副校長室／校務研究辦公室,
教務長室／綜合業務組) they stay one room with both names. 註冊課務組 (2F)
and 教務長室／綜合業務組 (3F) wrap round the lift lobby, as L-shaped rooms. Offices under 總務處 and 教務處 carry that office as their note,
so searching the office finds them. Floors hold several units each, so none
has a floor unit. Only the three conference rooms are numbered; they're
named with the number, as the signs do (101 會議室). No door is crossed out.
"""
import json
from pathlib import Path

W, D = 31.8, 52.3  # east–west, north–south
N_WING = 13.5  # the north wing's inner wall (its corridor included)
N_STAIR = 18.05  # the north stair's south side
S_STAIR = 33.25  # the south stair's north side
S_WING = 38.9  # the south wing's inner wall
COURT = 16.1  # the courtyard's east edge, and the stairs' east side
STAIR_W = 10.4  # the stairs' west side


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


def interp(stops, v):
    """Piecewise linear through (sign fraction, metres) stops."""
    for (a, x), (b, y) in zip(stops, stops[1:]):
        if v <= b or (b, y) == stops[-1]:
            return x + (v - a) / (b - a) * (y - x)


class Sign:
    """One photographed sign, east up. `corners` are the plan's TL, TR, BR,
    BL in pixels (1600 px long side); `wings` the pixels on the north wing's
    inner wall, the north stair's south side, the south stair's north side
    and the south wing's inner wall; `bands` the pixels on the courtyard's
    east edge and the stairs' west side."""

    def __init__(self, corners, wings, bands):
        a, b = [], []
        for (u, v), (s, t) in zip(corners, [(0, 0), (1, 0), (1, 1), (0, 1)]):
            a.append([u, v, 1, 0, 0, 0, -u * s, -v * s])
            b.append(s)
            a.append([0, 0, 0, u, v, 1, -u * t, -v * t])
            b.append(t)
        self.h = solve(a, b)
        s = [self.square(*p)[0] for p in wings]
        t = [self.square(*p)[1] for p in bands]
        # Sign left → right is north → south; top → bottom is east → west.
        self.ys = [(0, 0), (s[0], N_WING), (s[1], N_STAIR), (s[2], S_STAIR), (s[3], S_WING), (1, D)]
        self.xs = [(0, W), (t[0], COURT), (t[1], STAIR_W), (1, 0)]

    def square(self, u, v):
        h = self.h
        w = h[6] * u + h[7] * v + 1
        return (h[0] * u + h[1] * v + h[2]) / w, (h[3] * u + h[4] * v + h[5]) / w

    def x(self, v, u=600):
        """A wall across the sign at pixel row v, as metres east."""
        return round(interp(self.xs, self.square(u, v)[1]), 2)

    def y(self, u, v=700):
        """A wall down the sign at pixel column u, as metres south."""
        return round(interp(self.ys, self.square(u, v)[0]), 2)


def rect(kind, x0, y0, x1, y1, name=None, note=None, aka=None):
    """A box between wall lines, in metres; corners in any order."""
    x0, x1 = sorted((x0, x1))
    y0, y1 = sorted((y0, y1))
    space = {"kind": kind, "rect": [x0, y0, round(x1 - x0, 2), round(y1 - y0, 2)]}
    return labelled(space, name, note, aka)


def poly(kind, ps, name=None, note=None, aka=None):
    return labelled({"kind": kind, "polygon": [[x, y] for x, y in ps]}, name, note, aka)


def room(*box, name=None, note=None, aka=None):
    return rect("room", *box, name=name, note=note, aka=aka)


def labelled(space, name, note, aka):
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    if aka:
        space["aka"] = aka
    return space


def outline(cut=0):
    """The C round the courtyard; with `cut`, the north wing stops that far
    east of the west wall."""
    return [[cut, 0], [W, 0], [W, D], [0, D], [0, S_WING], [STAIR_W, S_WING], [STAIR_W, S_STAIR],
            [COURT, S_STAIR], [COURT, N_STAIR], [STAIR_W, N_STAIR], [STAIR_W, N_WING], [cut, N_WING]]


def stairs():
    """The two stairs filling the courtyard's inner corners."""
    return [rect("stairs", STAIR_W, N_WING, COURT, N_STAIR), rect("stairs", STAIR_W, S_STAIR, COURT, S_WING)]


def corridors(cut, north, south, east):
    """The corridor round the courtyard: along the north wing (from `north`
    to its inner wall), down the east band's courtyard side (to `east`) and
    along the south wing (from its inner wall to `south`)."""
    return [
        rect("corridor", cut, north, COURT, N_WING),
        rect("corridor", COURT, north, east, south),
        rect("corridor", 0, S_WING, COURT, south),
    ]


GA, AA = "總務處", "教務處"


def toilets(top, east, lobby, women, back, north, south):
    """The south-west toilets every floor shares, from the south wing's
    inner wall `top` to the south wall and from the west wall to `east`:
    men's east of `women`, women's west of it, and the accessible toilet
    between `north` and `south`, reached from a lobby off the corridor,
    from `lobby` west to `back`, cut into both."""
    return [
        poly("restroom", [(lobby, top), (east, top), (east, D), (women, D), (women, south), (lobby, south)],
             name="男廁"),
        poly("restroom", [(0, top), (back, top), (back, south), (women, south), (women, D), (0, D)], name="女廁"),
        rect("corridor", back, top, lobby, north),
        rect("restroom", back, north, lobby, south, name="無障礙廁所"),
    ]


def floor_1f():
    g = Sign([(125, 212), (1102, 244), (1120, 1145), (77, 1140)],
             [(352, 800), (502, 700), (722, 700), (859, 800)], [(600, 638), (430, 770)])
    north, south = g.y(297, 650), g.y(927, 800)  # the wings' rooms
    east = g.x(515)  # the east band's rooms
    split = g.x(700, 200)  # 文書組 | 事務組
    r102 = g.y(374, 400), g.y(510, 400)
    r101, tea, lift = g.y(730, 350), g.y(774, 490), g.y(867, 490)
    back101 = g.x(457, 800)
    centre = g.x(920, 1000)  # 教學發展中心's west end
    spaces = [
        *corridors(0, north, south, east),
        rect("corridor", east, r102[1], W, r101),  # the entrance hall
        rect("corridor", east, lift, back101, south),
        poly("room", [(split, 0), (W, 0), (W, r102[0]), (east, r102[0]), (east, north), (split, north)],
             name="文書組", note=GA),
        room(0, 0, split, north, name="事務組／採購組", note=GA),
        room(east, r102[0], W, r102[1], name="102 會議室"),
        room(back101, r101, W, south, name="101 會議室"),
        room(east, r101, back101, tea, name="茶水間"),
        rect("elevator", east, tea, back101, lift),
        room(centre, south, W, D, name="教學發展中心"),
        *toilets(south, centre, g.x(985, 1000), g.x(1032, 1000), g.x(1076, 1000), g.y(967, 1000),
                 g.y(1026, 1000)),
        *stairs(),
        # The open courtyard, outside the walls.
        poly("terrace", [(0, N_WING), (STAIR_W, N_WING), (STAIR_W, N_STAIR), (COURT, N_STAIR), (COURT, S_STAIR),
                         (STAIR_W, S_STAIR), (STAIR_W, S_WING), (0, S_WING)], name="中庭"),
    ]
    return {"id": "1F", "outline": outline(), "spaces": spaces}


def floor_2f():
    g = Sign([(116, 181), (1060, 221), (1072, 1073), (99, 1086)],
             [(360, 900), (496, 660), (706, 660), (831, 900)], [(430, 597), (430, 727)])
    north, south = g.y(296, 700), g.y(896, 700)
    east = g.x(482)
    wing = g.x(665, 200), g.x(865, 200)  # 營繕組 | 經營保管組 | 總務長室
    tea, lift = g.y(752, 460), g.y(840, 460)
    back = g.x(426, 800)  # 註冊課務組's west wall north of the lifts
    end = g.x(862, 1000)  # 註冊課務組's west end
    spaces = [
        *corridors(0, north, south, east),
        rect("corridor", east, lift, back, south),
        room(wing[0], 0, W, north, name="營繕組", note=GA),
        room(wing[1], 0, wing[0], north, name="經營保管組", note=GA),
        room(0, 0, wing[1], north, name="總務長室", note=GA),
        room(east, north, W, N_STAIR, name="出納組", note=GA),
        # Open to 1F's entrance hall below.
        rect("void", east, N_STAIR, W, S_STAIR),
        room(east, S_STAIR, back, tea, name="茶水間"),
        rect("elevator", east, tea, back, lift),
        poly("room", [(back, S_STAIR), (W, S_STAIR), (W, D), (end, D), (end, south), (back, south)],
             name="註冊課務組", note=AA),
        *toilets(south, end, g.x(925, 1000), g.x(967, 1000), g.x(1010, 1000), g.y(932, 1000), g.y(987, 1000)),
        *stairs(),
    ]
    return {"id": "2F", "outline": outline(), "spaces": spaces}


def floor_3f():
    g = Sign([(137, 241), (1090, 262), (1100, 1137), (112, 1131)],
             [(374, 850), (507, 700), (719, 700), (849, 900)], [(440, 650), (440, 780)])
    cut = g.x(915, 300)
    north, south = g.y(306, 800), g.y(916, 800)
    east = g.x(537)
    president = g.x(565, 200)
    row = g.y(587, 400), g.y(725, 400), g.y(857, 400)  # 秘書室 | 主任秘書室 | (room) | 教務長室
    tea = g.y(767, 500)
    back = g.x(475, 800)  # the room over the lifts, and 教務長室's west wall there
    dean = g.x(577, 1000)  # 教務長室's west wall beyond
    end = g.x(920, 1000)  # 301's west end
    spaces = [
        *corridors(cut, north, south, east),
        rect("corridor", east, row[2], back, south),
        room(president, 0, W, north, name="校長室"),
        room(cut, 0, president, north),
        room(east, north, W, row[0], name="秘書室"),
        room(east, row[0], W, row[1], name="主任秘書室"),
        room(back, row[1], W, row[2]),
        room(east, row[1], back, tea, name="茶水間"),
        rect("elevator", east, tea, back, row[2]),
        poly("room", [(back, row[2]), (W, row[2]), (W, D), (dean, D), (dean, south), (back, south)],
             name="教務長室／綜合業務組", note=AA),
        room(end, south, dean, D, name="301 會議室／校友會"),
        *toilets(south, end, g.x(984, 1000), g.x(1029, 1000), g.x(1070, 1000), g.y(953, 1000), g.y(1010, 1000)),
        *stairs(),
    ]
    return {"id": "3F", "outline": outline(cut), "spaces": spaces}


def floor_4f():
    g = Sign([(128, 121), (1156, 165), (1182, 1104), (90, 1107)],
             [(386, 900), (538, 640), (771, 640), (919, 900)], [(450, 570), (450, 715)])
    cut = g.x(862, 200)
    north, south = g.y(320, 500), g.y(980, 500)
    east = g.x(451)
    row, tea, lift = g.y(770, 300), g.y(820, 420), g.y(919, 420)
    back = g.x(382, 870)  # 環安中心's west wall
    end = g.x(866, 1080)  # 研究發展處's west end
    spaces = [
        *corridors(cut, north, south, east),
        rect("corridor", east, lift, back, south),
        room(cut, 0, W, north, name="主計室"),
        room(east, north, W, row, name="人事室"),
        room(back, row, W, south, name="環境保護暨職業安全衛生中心", aka=["環安中心"]),
        room(east, row, back, tea, name="茶水間"),
        rect("elevator", east, tea, back, lift),
        room(end, south, W, D, name="研究發展處", aka=["研發處", "研發企劃組", "計畫管理組", "產學推廣組"]),
        *toilets(south, end, g.x(937, 1050), g.x(985, 1050), g.x(1030, 1050), g.y(1030, 1000),
                 g.y(1091, 1000)),
        *stairs(),
    ]
    return {"id": "4F", "outline": outline(cut), "spaces": spaces}


def floor_5f():
    g = Sign([(215, 272), (1073, 316), (1062, 1100), (182, 1094)],
             [(428, 850), (543, 700), (730, 700), (847, 900)], [(480, 649), (480, 771)])
    cut = g.x(888, 300)
    corner, south = g.y(370, 600), g.y(910, 600)  # 國際事務處's east wall by the corridor; the south rooms
    east = g.x(545)
    row = g.y(503, 400), g.y(747, 400), south  # 第一 | 第二 | (room) | 學術副校長室
    tea, lift = g.y(781, 530), g.y(862, 530)
    back = g.x(505, 800)
    stub = g.y(453, 480), g.x(427, 480)  # the corridor's stub into 第一會議室
    vp = g.x(662, 1000)  # 學術副校長室 | 行政副校長室
    end = g.x(908, 1000)
    spaces = [
        rect("corridor", COURT, corner, east, south),
        rect("corridor", 0, S_WING, COURT, south),
        rect("corridor", east, stub[0], stub[1], row[0]),
        rect("corridor", east, lift, back, row[2]),
        poly("room", [(east, 0), (W, 0), (W, row[0]), (stub[1], row[0]), (stub[1], stub[0]), (east, stub[0])],
             name="第一會議室"),
        poly("room", [(cut, 0), (east, 0), (east, corner), (COURT, corner), (COURT, N_WING), (cut, N_WING)],
             name="國際事務處"),
        room(east, row[0], W, row[1], name="第二會議室"),
        room(back, row[1], W, row[2]),
        room(east, row[1], back, tea, name="茶水間"),
        rect("elevator", east, tea, back, lift),
        room(vp, row[2], W, D, name="學術副校長室／校務研究辦公室"),
        room(end, row[2], vp, D, name="行政副校長室"),
        *toilets(row[2], end, g.x(963, 1000), g.x(1005, 1000), g.x(1040, 1000), g.y(933, 1000), g.y(985, 1000)),
        *stairs(),
    ]
    return {"id": "5F", "outline": outline(cut), "spaces": spaces}


def main():
    floors = [f() for f in (floor_1f, floor_2f, floor_3f, floor_4f, floor_5f)]
    building = {"id": "xingzheng", "name": "行政大樓", "unit": "m", "floors": floors}
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/xingzheng.json", root / "mobile/assets/campus_map/xingzheng.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
