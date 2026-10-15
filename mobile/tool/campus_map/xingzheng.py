#!/usr/bin/env python3
"""Generates app-content/campus-map/xingzheng.json (行政大樓).

Measured from the floor plan on each floor's stair landing (1F–5F) and fitted
to the OpenStreetMap outline, 32.7 × 52.8 m. The signs are drawn east up:
the main entrance (正門入口) at the top of the 1F sign is on the east side,
the left wing is north, the right wing south, and the courtyard (中庭) at the
bottom opens to the west. North up, the building is a C open to the west,
with a stair in each inner corner of the courtyard.

The signs aren't to scale, so each photo is first squared up by its four
corners (a projective map, which also takes out the camera's slant), then
stretched piecewise between the lines the building and the signs share: the
wings' inner walls, the stairs' sides and the courtyard's east edge. A last
bilinear step bends that rectangle onto OSM's slightly skewed outline.

On 3F–5F the north wing stops short of the west wall (all three signs draw
the courtyard running past its end), so those floors' outlines are cut
there. 2F has an open void over the entrance lobby.

Rooms are the administrative units named on the signs and the lift
directory; where a sign draws two units in one box with no wall between
(教務長室／綜合業務組, 301 會議室／校友會, 事務組／採購組, 學術副校長室／
校務研究辦公室) they stay one room with both names. Offices under 總務處 and
教務處 carry that office as their note, so searching the office finds them.
Floors hold several units each, so none has a floor unit. Only the three
conference rooms are numbered; they're named with the number, as the signs
do (101 會議室). No door is crossed out.
"""
import json
from pathlib import Path

# OSM way 256119623 in metres east and south of its bounding box's NW corner.
OSM = [[0.0, 0.5], [0.3, 14.0], [10.5, 13.8], [10.5, 18.4], [16.3, 18.3], [16.4, 21.1], [16.6, 31.3],
       [16.6, 33.5], [11.0, 33.6], [11.1, 39.2], [0.5, 39.4], [0.8, 52.8], [32.7, 52.3], [31.7, 0.0]]
NW, NE, SE, SW = OSM[0], OSM[13], OSM[12], OSM[11]

# The building squared up: W east–west, D north–south, and the lines the
# signs share, from OSM's notch corners.
W, D = 31.8, 52.3
N_WING = 13.5  # the north wing's inner wall (its corridor included)
N_STAIR = 18.05  # the north stair's south side
S_STAIR = 33.25  # the south stair's north side
S_WING = 38.9  # the south wing's inner wall
COURT = 16.1  # the courtyard's east edge, and the stairs' east side
STAIR_W = 10.4  # the stairs' west side


def bend(x, y):
    """The squared-up frame onto OSM's outline (bilinear by its corners)."""
    s, t = x / W, y / D
    return [round((1 - s) * (1 - t) * NW[i] + s * (1 - t) * NE[i] + s * t * SE[i] + (1 - s) * t * SW[i], 2)
            for i in (0, 1)]


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

    def frame(self, u, v):
        """Pixels to the squared-up frame, metres."""
        s, t = self.square(u, v)
        return interp(self.xs, t), interp(self.ys, s)

    def pt(self, u, v):
        return bend(*self.frame(u, v))

    def poly(self, kind, ps, name=None, note=None, aka=None):
        space = {"kind": kind, "polygon": [self.pt(*p) for p in ps]}
        return labelled(space, name, note, aka)

    def rect(self, kind, u0, v0, u1, v1, name=None, note=None, aka=None):
        return self.poly(kind, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], name, note, aka)

    def room(self, *box, name=None, note=None, aka=None):
        return self.rect("room", *box, name=name, note=note, aka=aka)

    def outline(self, north_end=None):
        """OSM's outline; with `north_end` (a pixel row), the north wing cut
        short there."""
        if north_end is None:
            return OSM
        x = round(interp(self.xs, self.square(0, north_end)[1]), 2)
        return [bend(x, 0), bend(x, N_WING)] + OSM[2:]


def labelled(space, name, note, aka):
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    if aka:
        space["aka"] = aka
    return space


GA, AA = "總務處", "教務處"


def toilets(g, men, lobby, accessible, women):
    """The south-west toilets every floor shares: men's to the east, women's
    to the west, the accessible one off a small lobby between. Each box is
    (u0, v0, u1, v1); men's and women's wrap round the accessible toilet."""
    m0, m1, m2, m3 = men
    l0, l1, l2, l3 = lobby
    a0, a1, a2, a3 = accessible
    w0, w1, w2, w3 = women
    return [
        g.poly("restroom", [(m0, m1), (m2, m1), (m2, m3), (a2, m3), (a2, a1), (l2, a1), (l2, l1), (m0, l1)],
               name="男廁"),
        g.rect("corridor", l0, l1, l2, l3),
        g.rect("restroom", a0, a1, a2, a3, name="無障礙廁所"),
        g.poly("restroom", [(a2, w1), (w2, w1), (w2, w3), (w0, w3), (w0, l3), (a2, l3)], name="女廁"),
    ]


def floor_1f():
    g = Sign([(125, 212), (1102, 244), (1120, 1145), (77, 1140)],
             [(352, 800), (502, 700), (722, 700), (859, 800)], [(600, 638), (430, 770)])
    spaces = [
        g.rect("corridor", 510, 222, 730, 520),
        g.rect("corridor", 300, 515, 928, 638),
        g.rect("corridor", 297, 638, 352, 1140),
        g.rect("corridor", 858, 638, 928, 1145),
        g.poly("room", [(125, 212), (374, 219), (374, 515), (300, 512), (297, 700), (107, 700)],
               name="文書組", note=GA),
        g.poly("room", [(107, 700), (297, 700), (276, 1140), (77, 1140)], name="事務組／採購組", note=GA),
        g.room(374, 219, 510, 515, name="102 會議室"),
        g.room(730, 229, 925, 457, name="101 會議室"),
        g.room(727, 457, 774, 525, name="茶水間"),
        g.rect("elevator", 774, 457, 867, 525),
        g.room(925, 240, 1110, 920, name="教學發展中心"),
        *toilets(g, (925, 920, 1116, 1032), (927, 985, 967, 1076), (967, 987, 1026, 1076), (930, 1032, 1120, 1145)),
        g.rect("stairs", 365, 632, 500, 770),
        g.rect("stairs", 722, 640, 858, 775),
        # The open courtyard, outside the walls.
        g.poly("terrace", [(502, 638), (722, 640), (722, 776), (860, 776), (860, 1145), (350, 1140),
                           (352, 770), (502, 770)], name="中庭"),
    ]
    return {"id": "1F", "outline": g.outline(), "spaces": spaces}


def floor_2f():
    g = Sign([(116, 181), (1060, 221), (1072, 1073), (99, 1086)],
             [(360, 900), (496, 660), (706, 660), (831, 900)], [(430, 597), (430, 727)])
    spaces = [
        g.rect("corridor", 296, 482, 896, 597),
        g.rect("corridor", 840, 427, 895, 482),
        g.rect("corridor", 296, 597, 360, 1085),
        g.rect("corridor", 831, 597, 898, 1072),
        g.poly("room", [(116, 181), (301, 190), (296, 665), (105, 664)], name="營繕組", note=GA),
        g.room(105, 664, 296, 865, name="經營保管組", note=GA),
        g.poly("room", [(102, 865), (296, 865), (290, 1085), (99, 1085)], name="總務長室", note=GA),
        g.room(302, 191, 496, 482, name="出納組", note=GA),
        # Open to 1F's entrance lobby below.
        g.rect("void", 497, 195, 706, 482),
        g.room(707, 425, 752, 492, name="茶水間"),
        g.rect("elevator", 752, 427, 840, 492),
        g.poly("room", [(707, 207), (1060, 221), (1067, 862), (896, 862), (895, 427), (707, 425)],
               name="註冊課務組", note=AA),
        *toilets(g, (896, 862, 1069, 967), (898, 925, 932, 1010), (932, 927, 987, 1007), (898, 967, 1072, 1072)),
        g.rect("stairs", 364, 596, 496, 727),
        g.rect("stairs", 706, 602, 831, 730),
    ]
    return {"id": "2F", "outline": g.outline(), "spaces": spaces}


def floor_3f():
    g = Sign([(137, 241), (1090, 262), (1100, 1137), (112, 1131)],
             [(374, 850), (507, 700), (719, 700), (849, 900)], [(440, 650), (440, 780)])
    spaces = [
        g.rect("corridor", 306, 537, 915, 650),
        g.rect("corridor", 857, 475, 915, 537),
        g.rect("corridor", 306, 650, 374, 915),
        g.rect("corridor", 849, 577, 916, 1135),
        g.poly("room", [(137, 241), (317, 246), (317, 565), (130, 565)], name="校長室"),
        g.poly("room", [(130, 565), (317, 565), (306, 915), (118, 915)]),
        g.room(317, 246, 587, 536, name="秘書室"),
        g.room(587, 250, 725, 537, name="主任秘書室"),
        g.room(725, 255, 857, 475),
        g.room(725, 475, 767, 537, name="茶水間"),
        g.rect("elevator", 767, 475, 857, 540),
        g.poly("room", [(857, 257), (1090, 262), (1090, 577), (915, 577), (915, 475), (857, 475)],
               name="教務長室／綜合業務組", note=AA),
        g.room(914, 577, 1094, 920, name="301 會議室／校友會"),
        *toilets(g, (916, 920, 1098, 1029), (916, 984, 953, 1070), (953, 986, 1010, 1070), (918, 1029, 1099, 1136)),
        g.rect("stairs", 376, 650, 507, 780),
        g.rect("stairs", 719, 654, 849, 782),
    ]
    return {"id": "3F", "outline": g.outline(north_end=915), "spaces": spaces}


def floor_4f():
    g = Sign([(128, 121), (1156, 165), (1182, 1104), (90, 1107)],
             [(386, 900), (538, 640), (771, 640), (919, 900)], [(450, 570), (450, 715)])
    spaces = [
        g.rect("corridor", 314, 441, 987, 570),
        g.rect("corridor", 919, 386, 974, 451),
        g.rect("corridor", 314, 570, 386, 862),
        g.rect("corridor", 913, 575, 990, 1104),
        g.poly("room", [(128, 121), (329, 128), (314, 862), (99, 862)], name="主計室"),
        g.poly("room", [(329, 131), (770, 148), (770, 451), (329, 441)], name="人事室"),
        g.room(770, 151, 974, 382, name="環境保護暨職業安全衛生中心", aka=["環安中心"]),
        g.room(772, 382, 820, 454, name="茶水間"),
        g.rect("elevator", 820, 382, 919, 451),
        g.poly("room", [(974, 160), (1156, 165), (1177, 867), (987, 866)], name="研究發展處",
               aka=["研發處", "研發企劃組", "計畫管理組", "產學推廣組"]),
        *toilets(g, (987, 867, 1177, 985), (987, 937, 1030, 1030), (1030, 939, 1091, 1030), (994, 985, 1182, 1104)),
        g.rect("stairs", 391, 566, 538, 712),
        g.rect("stairs", 771, 575, 913, 718),
    ]
    return {"id": "4F", "outline": g.outline(north_end=862), "spaces": spaces}


def floor_5f():
    g = Sign([(215, 272), (1073, 316), (1062, 1100), (182, 1094)],
             [(428, 850), (543, 700), (730, 700), (847, 900)], [(480, 649), (480, 771)])
    spaces = [
        g.rect("corridor", 370, 543, 903, 649),
        g.rect("corridor", 453, 427, 503, 543),
        g.rect("corridor", 862, 505, 912, 560),
        g.rect("corridor", 847, 649, 903, 1095),
        g.poly("room", [(215, 272), (503, 285), (503, 427), (453, 427), (453, 543), (370, 546), (206, 536)],
               name="第一會議室"),
        g.poly("room", [(206, 536), (370, 546), (370, 649), (428, 649), (420, 890), (190, 888)],
               name="國際事務處"),
        g.room(503, 290, 747, 545, name="第二會議室"),
        g.room(747, 302, 914, 505),
        g.room(741, 502, 781, 563, name="茶水間"),
        g.rect("elevator", 781, 503, 862, 560),
        g.room(914, 312, 1073, 662, name="學術副校長室／校務研究辦公室"),
        g.room(903, 662, 1065, 908, name="行政副校長室"),
        *toilets(g, (902, 908, 1063, 1005), (902, 963, 933, 1040), (933, 965, 985, 1040), (903, 1005, 1062, 1100)),
        g.rect("stairs", 428, 649, 543, 771),
        g.rect("stairs", 730, 650, 848, 778),
    ]
    return {"id": "5F", "outline": g.outline(north_end=888), "spaces": spaces}


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
