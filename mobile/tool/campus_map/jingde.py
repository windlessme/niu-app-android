#!/usr/bin/env python3
"""Generates app-content/campus-map/jingde.json (經德大樓).

Read off the evacuation map on each floor and fitted to the 54.8 × 50.5 m
OpenStreetMap outline by four corners each, a projective map that also
takes out the camera's slant. The building is a ring of rooms round an
open courtyard: a north block, and a south wing that reaches 6 m further
west and east. North is up.

The signs hang different ways round. 1F, 3F and 4F are north up; 5F and 6F
are drawn upside down (south up, the toilets on the left); 7F has west up
and north on the right. Each floor's own lifts, stairs and toilets in the
corners confirm the turn.

2F has no evacuation map, only a directory poster that is not to scale;
its rooms are placed on 3F's sign, which shares the walls, in the order
and proportions the poster shows. The poster gives the rooms' codes, 經
plus a number (經201), so they go in `code`. 6F and 7F are 國立空中大學's
宜蘭學習指導中心; its own boards name some classrooms 6B–6D and 7A–7C,
kept in `aka`.

1F has no rooms west of the north block's line: the south wing's west end
there is the outside ramp and stair. The room by the north-west stair is
labelled by hand on tape (書店, 咖啡・文創). 3F's map still prints older
names; the board beside it lists 生物機電工程學系's rooms 301–312 without
saying where they are, so the floor carries the department but the rooms
keep the map's names.
"""
import json
from pathlib import Path

# The OpenStreetMap outline, metres east and south of its bounding box's
# north-west corner.
OUTLINE = [[5.5, 1.0], [34.3, 0.3], [45.6, 0.0], [45.9, 12.1], [48.3, 12.1], [48.8, 34.3], [54.5, 34.2],
           [54.8, 49.2], [0.6, 50.5], [0.0, 28.8], [6.2, 28.7]]
NW, NE, SE, SW = (5.5, 1.0), (45.6, 0.0), (54.8, 49.2), (0.6, 50.5)
SPACE = "國立空中大學宜蘭學習指導中心"


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


class Sign:
    """One photographed sign: four pixel points and where they are in metres
    (east, south), as a projective map."""

    def __init__(self, pairs):
        a, b = [], []
        for (u, v), (x, y) in pairs:
            a.append([u, v, 1, 0, 0, 0, -u * x, -v * x])
            b.append(x)
            a.append([0, 0, 0, u, v, 1, -u * y, -v * y])
            b.append(y)
        self.h = solve(a, b)

    def pt(self, u, v):
        h = self.h
        w = h[6] * u + h[7] * v + 1
        return [round((h[0] * u + h[1] * v + h[2]) / w, 2), round((h[3] * u + h[4] * v + h[5]) / w, 2)]

    def pts(self, ps):
        return [self.pt(*p) for p in ps]

    def poly(self, kind, ps, name=None, note=None, code=None, aka=None):
        return labelled({"kind": kind, "polygon": self.pts(ps)}, name, note, code, aka)

    def rect(self, kind, u0, v0, u1, v1, name=None, note=None, code=None, aka=None):
        """A box on the sign: a rectangle in metres unless the photo's slant
        skews it noticeably."""
        ps = self.pts([(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
        xs, ys = [p[0] for p in ps], [p[1] for p in ps]
        area = abs(sum(p[0] * q[1] - q[0] * p[1] for p, q in zip(ps, ps[1:] + ps[:1]))) / 2
        x0, y0 = min(xs), min(ys)
        if area > .96 * (max(xs) - x0) * (max(ys) - y0):
            space = {"kind": kind, "rect": [x0, y0, round(max(xs) - x0, 2), round(max(ys) - y0, 2)]}
        else:
            space = {"kind": kind, "polygon": ps}
        return labelled(space, name, note, code, aka)

    def room(self, *box, **label):
        return self.rect("room", *box, **label)


def labelled(space, name, note, code, aka):
    if code:
        space["code"] = f"經{code}"
    if aka:
        space["aka"] = aka
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


def north_up(nw, ne, se, sw):
    return Sign([(nw, NW), (ne, NE), (se, SE), (sw, SW)])


# 3F's map, north up; 2F's rooms are placed on it too.
THIRD = north_up((683, 265), (1310, 255), (1420, 975), (518, 975))


def ring(g, rooms):
    """What 2F and 3F share on sign `g`: stairs, lifts, toilets and the
    unnamed boxes either side of the east rooms, plus `rooms`."""
    return [
        g.rect("stairs", 770, 310, 818, 378),
        g.rect("restroom", 1188, 255, 1248, 360, name="女廁"),
        g.rect("restroom", 1248, 255, 1310, 372, name="男廁"),
        g.rect("stairs", 1263, 375, 1312, 430),
        g.room(1228, 425, 1316, 478),
        g.room(1245, 737, 1330, 800),
        g.rect("stairs", 683, 672, 775, 735),
        g.rect("elevator", 735, 735, 780, 800),
        g.rect("stairs", 1365, 790, 1415, 845),
        g.rect("restroom", 1290, 860, 1352, 975, name="女廁"),
        g.rect("restroom", 1352, 860, 1420, 975, name="男廁"),
    ] + rooms


def floor_1f():
    # North up. The south wing stops at the north block's west wall; the
    # ramp and stair outside it are open air.
    g = Sign([((640, 292), NW), ((1230, 283), NE), ((1335, 970), SE), ((630, 970), (6.7, 50.35))])
    spaces = [
        g.rect("stairs", 672, 340, 712, 405),
        g.room(712, 292, 857, 405, name="書店", note="咖啡・文創"),
        g.room(857, 290, 1004, 405, name="研究室（一）（二）"),
        g.room(1004, 288, 1117, 400, name="研究室（三）"),
        g.rect("restroom", 1117, 285, 1170, 378, name="女廁"),
        g.rect("restroom", 1170, 283, 1230, 378, name="男廁"),
        g.rect("stairs", 1158, 400, 1222, 445),
        g.rect("stairs", 600, 410, 640, 490),
        g.rect("terrace", 782, 440, 1050, 805, name="中庭平台"),
        g.rect("stairs", 782, 500, 880, 550),
        g.rect("stairs", 782, 730, 888, 762),
        g.room(1090, 500, 1247, 740, name="電腦教室"),
        g.rect("stairs", 648, 678, 712, 738),
        g.rect("elevator", 672, 752, 705, 800),
        g.rect("stairs", 1270, 815, 1320, 850),
        g.room(630, 840, 782, 970, name="文書組辦公室"),
        g.room(782, 870, 840, 970, name="檔案室"),
        g.room(840, 870, 897, 970, name="檔案室"),
        g.room(897, 840, 1090, 970, name="進修部辦公室"),
        g.room(1090, 840, 1213, 970, name="進修部"),
        g.rect("restroom", 1213, 850, 1265, 970, name="女廁"),
        g.rect("restroom", 1265, 855, 1335, 970, name="男廁"),
    ]
    outline = g.pts([(640, 292), (1230, 283), (1230, 445), (1247, 445), (1247, 850), (1335, 850), (1335, 970),
                     (630, 970)])
    return {"id": "1F", "outline": outline, "spaces": spaces}


def floor_2f():
    # The directory poster, laid on 3F's sign. Its south row of eight rooms
    # is spread over 3F's south rooms in the poster's proportions.
    g = THIRD
    south = [
        ("學部長辦公室", None, None, "博雅學部"),
        ("博雅學部", "201", ["經202"], None),
        ("陳復老師研究室", "203", None, None),
        ("廖玉卿老師研究室", None, None, None),
        ("林德誠老師研究室", "204", None, None),
        ("社群老師討論室", None, None, None),
        ("劉文琴老師研究室", "205", None, None),
        ("鍾鴻銘老師研究室", None, None, None),
    ]
    edges = [518, 613, 773, 865, 956, 1036, 1131, 1212, 1290]
    rooms = [g.room(a, 845, b, 975, name=n, code=c, aka=k, note=t)
             for (a, b), (n, c, k, t) in zip(zip(edges, edges[1:]), south)]
    spaces = ring(g, [
        g.room(838, 265, 968, 378, name="博雅學部會議室", code="211"),
        g.room(968, 262, 1093, 378, name="生命教育心靈空間教室", code="210"),
        g.room(1093, 258, 1188, 375, name="黃春明研究中心", code="209"),
        g.rect("void", 838, 420, 1112, 800, name="中庭"),
        g.room(1157, 478, 1330, 735, name="黃春明講座教授研究室", code="208"),
        g.room(518, 672, 578, 800, name="王進發老師研究室"),
        g.room(578, 672, 683, 800, name="林大森老師研究室", code="206"),
        *rooms,
    ])
    return {"id": "2F", "outline": OUTLINE, "spaces": spaces, "unit": "博雅學部"}


def floor_3f():
    g = THIRD
    spaces = ring(g, [
        g.room(838, 265, 992, 378, name="普通教室"),
        g.room(992, 262, 1110, 378, name="普通教室"),
        g.room(1110, 258, 1188, 375, name="普通教室"),
        g.room(683, 425, 795, 672, name="導師休息室"),
        g.rect("void", 838, 420, 1112, 800),
        g.room(1157, 478, 1330, 735, name="園藝系景觀研究室"),
        g.room(518, 672, 683, 800, name="輔導室"),
        g.room(518, 845, 718, 975, name="普通教室"),
        g.room(718, 845, 838, 975, name="普通教室"),
        g.room(838, 845, 1070, 975, name="普通教室"),
        g.room(1070, 845, 1290, 975, name="機械科辦公室"),
    ])
    return {"id": "3F", "outline": OUTLINE, "spaces": spaces, "unit": "生物機電工程學系", "aliases": ["生機系"]}


def floor_4f():
    g = north_up((695, 228), (1332, 225), (1422, 948), (535, 948))
    spaces = [
        g.rect("stairs", 785, 278, 842, 355),
        g.room(852, 228, 1012, 355, name="教室"),
        g.room(1012, 228, 1071, 350, name="教室"),
        g.room(1071, 228, 1132, 350, name="教室"),
        g.room(1132, 228, 1212, 350, name="教室"),
        g.rect("restroom", 1212, 228, 1268, 345, name="女廁"),
        g.rect("restroom", 1268, 228, 1332, 350, name="男廁"),
        g.rect("stairs", 1285, 350, 1335, 415),
        g.room(1245, 415, 1337, 457),
        g.room(695, 395, 812, 648, name="化工科實驗室"),
        g.rect("void", 852, 393, 1132, 777),
        g.room(1175, 457, 1337, 713, name="製圖教室"),
        g.room(1258, 713, 1337, 777),
        g.rect("stairs", 1370, 768, 1420, 820),
        g.room(535, 648, 615, 775, name="化工科"),
        g.room(615, 648, 695, 775, name="化工科辦公室"),
        g.rect("stairs", 695, 648, 775, 710),
        g.rect("elevator", 735, 712, 775, 775),
        g.room(535, 818, 695, 948, name="PLC實驗室"),
        g.room(695, 818, 853, 948, name="PLC實驗室"),
        g.room(853, 818, 1015, 948, name="電子工廠"),
        g.room(1015, 818, 1178, 948, name="繞線工廠"),
        g.room(1178, 818, 1300, 948, name="退休教師聯誼會"),
        g.rect("restroom", 1300, 830, 1357, 948, name="女廁"),
        g.rect("restroom", 1357, 830, 1420, 948, name="男廁"),
    ]
    return {"id": "4F", "outline": OUTLINE, "spaces": spaces}


def south_up(se, sw, nw, ne):
    """An upside-down sign by its corners: top left is the south-east."""
    return Sign([(se, SE), (sw, SW), (nw, NW), (ne, NE)])


def floor_5f():
    g = south_up((572, 252), (1418, 262), (1250, 942), (640, 942))
    spaces = [
        g.rect("restroom", 572, 252, 625, 378, name="男廁"),
        g.rect("restroom", 625, 252, 688, 360, name="女廁"),
        g.room(688, 252, 803, 375, name="經管所研討室", note="多功能教室"),
        g.room(803, 255, 958, 372, name="經管所教師研究室"),
        g.room(958, 256, 1033, 372, name="經管所教師研究室"),
        g.room(1033, 257, 1110, 370, name="經管所教師研究室"),
        g.room(1110, 258, 1265, 365, name="事務組・環安衛生組"),
        g.room(1265, 262, 1418, 362, name="視聽教室・物理教室（二）"),
        g.rect("stairs", 572, 377, 622, 422),
        g.room(645, 418, 725, 478),
        g.room(645, 478, 797, 640, name="實驗室"),
        g.room(645, 640, 797, 720),
        g.room(643, 720, 727, 775),
        g.rect("stairs", 640, 778, 700, 828),
        g.rect("void", 838, 422, 1103, 790),
        g.rect("elevator", 1183, 425, 1222, 490),
        g.room(1222, 440, 1258, 490, name="辦公室"),
        g.rect("stairs", 1183, 490, 1258, 548),
        g.room(1258, 440, 1335, 553, name="物理科辦公室"),
        g.room(1335, 440, 1410, 553, name="辦公室"),
        g.room(1138, 553, 1250, 800, name="器材室"),
        g.rect("restroom", 640, 828, 700, 942, name="男廁"),
        g.rect("restroom", 700, 845, 755, 942, name="女廁"),
        g.room(755, 828, 828, 942, name="經管所行銷調查實驗室"),
        g.room(828, 828, 942, 942, name="經管所學生研究室", note="電腦教室・辦公室"),
        g.room(942, 828, 1020, 885, name="教師研究室"),
        g.room(942, 885, 1020, 942, name="經管所所長室"),
        g.room(1020, 828, 1095, 942, name="經管所辦公室"),
        g.rect("stairs", 1100, 825, 1160, 905),
    ]
    return {"id": "5F", "outline": OUTLINE, "spaces": spaces}


def floor_6f():
    g = south_up((517, 238), (1375, 245), (1228, 947), (605, 955))
    spaces = [
        g.rect("restroom", 517, 238, 583, 368, name="男廁"),
        g.rect("restroom", 583, 238, 640, 340, name="女廁"),
        g.room(640, 240, 837, 368, name="教室", aka=["6B"]),
        g.room(837, 241, 1072, 365, name="電腦教室"),
        g.room(1072, 243, 1225, 362, name="辦公室"),
        g.room(1225, 244, 1301, 360, name="導師室"),
        g.room(1301, 245, 1375, 360, name="主任室"),
        g.rect("stairs", 517, 362, 575, 418),
        g.room(600, 410, 683, 473),
        g.room(603, 473, 762, 603, name="教室", aka=["6C"]),
        g.room(603, 603, 762, 722, name="教室", aka=["6D"]),
        g.room(605, 725, 690, 780),
        g.rect("void", 800, 410, 1072, 782),
        g.rect("elevator", 1148, 410, 1186, 470),
        g.room(1186, 420, 1225, 470, name="辦公室"),
        g.rect("stairs", 1148, 470, 1225, 530),
        g.room(1225, 410, 1302, 530, name="諮商輔導室"),
        g.room(1302, 410, 1375, 530, name="會議室"),
        g.rect("stairs", 609, 780, 657, 830),
        g.rect("restroom", 605, 830, 668, 955, name="男廁"),
        g.rect("restroom", 668, 840, 725, 955, name="女廁"),
        g.room(725, 830, 805, 955, name="幼兒活動室"),
        g.room(805, 830, 920, 950, name="社團辦公室"),
        g.room(920, 830, 1075, 948, name="教室"),
        g.rect("stairs", 1080, 820, 1120, 900),
    ]
    return {"id": "6F", "outline": OUTLINE, "spaces": spaces, "unit": SPACE, "aliases": ["空大"]}


def floor_7f():
    # West up, north on the right.
    g = Sign([((720, 228), SW), ((1403, 385), NW), ((1362, 962), NE), ((720, 1005), SE)])
    spaces = [
        g.room(720, 228, 875, 459, name="學生收視閱覽室"),
        g.room(879, 228, 1000, 375, name="錄音、影帶儲藏室"),
        g.room(895, 385, 955, 425, name="辦公室"),
        g.rect("elevator", 880, 425, 935, 460),
        g.rect("stairs", 935, 385, 1000, 460),
        g.rect("stairs", 1272, 478, 1318, 540),
        g.room(720, 532, 828, 710, name="圖書館"),
        g.room(720, 710, 828, 912, name="綜合教室", aka=["7A"]),
        g.rect("restroom", 720, 912, 805, 960, name="女廁"),
        g.rect("restroom", 720, 960, 830, 1005, name="男廁"),
        g.rect("stairs", 828, 975, 872, 1020),
        g.poly("void", [(870, 540), (1230, 540), (1215, 790), (870, 780)]),
        g.room(920, 817, 1127, 957, name="演講廳", aka=["7B"]),
        g.room(865, 885, 920, 955),
        g.room(1148, 890, 1200, 965),
        g.rect("stairs", 1127, 838, 1160, 880),
        g.room(1252, 600, 1390, 758, name="教室", aka=["7C"]),
        g.room(1250, 758, 1385, 863, name="值夜室"),
        g.rect("restroom", 1250, 863, 1375, 910, name="女廁"),
        g.rect("restroom", 1250, 910, 1365, 962, name="男廁"),
        g.rect("stairs", 1200, 925, 1240, 970),
    ]
    return {"id": "7F", "outline": OUTLINE, "spaces": spaces, "unit": SPACE, "aliases": ["空大"]}


def main():
    floors = [f() for f in (floor_1f, floor_2f, floor_3f, floor_4f, floor_5f, floor_6f, floor_7f)]
    building = {"id": "jingde", "name": "經德大樓", "unit": "m", "floors": floors}
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/jingde.json", root / "mobile/assets/campus_map/jingde.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
