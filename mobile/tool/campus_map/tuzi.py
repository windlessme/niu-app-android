#!/usr/bin/env python3
"""Generates app-content/campus-map/tuzi.json (圖書資訊中心).

Seven floors, each read off a photo of its sign and fitted to the 75 × 48 m
OpenStreetMap outline by four corners, which also takes out the camera's
slant. The library's floor guides (2F–6F) are drawn north up; the
emergency maps for B1, 1F and 7F are not: 1F and B1 put east up and north
on the left, 7F west up and north on the right. The north-west wall is the
slanted one, beside 農權路.

1F's east half keeps the names on 電算中心's own guide; the offices west
of it are the emergency map's. The building is shared: the north-west wing
(the lecture halls, the library's offices on 4F, 數位學習資源中心 on 5F,
the old periodicals on 6F, with its own stairs and lift) is reached only by
its own entrance on 1F, not from the library, and 1F's offices are closed
to the public. The user outlined both on the signs (細節/), and they are
`zones` here.
B1 is 創新育成中心, aligned to 1F by the lifts and stairs the two share.
Rooms carry no codes: the library names them, numbers and all (523
討論室).
"""
import json
from pathlib import Path

EW, NS = 75.0, 48.0


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

    def raw(self, u, v):
        h = self.h
        w = h[6] * u + h[7] * v + 1
        return (h[0] * u + h[1] * v + h[2]) / w, (h[3] * u + h[4] * v + h[5]) / w

    def pt(self, u, v):
        x, y = self.raw(u, v)
        return [round(x, 2), round(y, 2)]

    def pts(self, ps):
        return [self.pt(*p) for p in ps]

    def poly(self, kind, ps, name=None, note=None):
        return labelled({"kind": kind, "polygon": self.pts(ps)}, name, note)

    def rect(self, kind, u0, v0, u1, v1, name=None, note=None):
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
        return labelled(space, name, note)

    def room(self, *box, name=None, note=None):
        return self.rect("room", *box, name=name, note=note)

    def zone(self, ps, name, note=None, entrance=None):
        """A part of the floor set apart; entrance is (pixel on the wall, the
        way in): its sign stands outside, pointing in."""
        z = {"name": name, "polygon": self.pts(ps)}
        if note:
            z["note"] = note
        if entrance:
            z["entrance"] = {"at": self.pt(*entrance[0]), "toward": list(entrance[1])}
        return z


# The wing only its own entrance on 1F reaches.
WING = "獨立區域"
WING_NOTE = "由 1 樓獨立入口進出"


def labelled(space, name, note):
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


def library(nw, sw, se, ne):
    """A north-up library guide by its corners: the north-west corner, the
    south-west, the south-east, and the east wing's north-east."""
    return Sign([(nw, (0, 0)), (sw, (0, NS)), (se, (EW, NS)), (ne, (EW, 23.1))])


# The library floors' outline in metres: the long south wall, the slanted
# north-west wall, and the narrower east wing.
LIBRARY = [[0, 0], [42.1, 13.1], [42.1, 23.1], [EW, 23.1], [EW, NS], [0, NS]]


# 1F's emergency map, east up and north on the left; two photo crops of it
# share these pixels (the lower one is offset, see `low`).
FIRST = Sign([((290.6, 1409), (0, 0)), ((905, 1409), (0, NS)), ((889, 520.6), (EW, NS)), ((595.6, 520.6), (EW, 23.1))])


def high(x, y):
    return 280 + x / 1.6, 430 + y / 1.6


def low(x, y):
    return 280 + x / 1.6, 1000 + y / 1.6


def floor_b1():
    # B1's map is drawn larger than 1F's; matched to it by the lifts and
    # stairs at its west end and east side.
    def to_1f(x, y):
        u, v = 330 + x / 1.1, 420 + y / 1.1
        return 376 + (u - 459) / 1.36, 1332 + (v - 1276) / 1.36

    class B1(Sign):
        def __init__(self):
            pass

        def raw(self, u, v):
            return FIRST.raw(*to_1f(u, v))

    g = B1()

    def slant(y):
        """The rooms' west wall, which follows the street."""
        return 295 - (y - 285) * .3

    spaces = [
        g.poly("terrace", [(300, 0), (470, 0), (470, 285), (225, 285)]),
        g.rect("stairs", 330, 60, 390, 170),
        g.room(470, 215, 545, 300, name="電信機房"),
        g.rect("elevator", 508, 380, 545, 418),
        g.poly("room", [(slant(285), 285), (390, 285), (390, 350), (slant(350), 350)], name="企業培育室七"),
        g.poly("room", [(slant(350), 350), (385, 350), (385, 420), (slant(420), 420)], name="企業培育室六"),
        *[g.poly("room", [(slant(y0), y0), (325, y0), (325, y1), (slant(y1), y1)], name=f"企業培育室{n}")
          for n, y0, y1 in (("五", 420, 505), ("四", 505, 570), ("三", 570, 640), ("二", 640, 730))],
        g.room(235, 730, 325, 850, name="企業培育室一"),
        g.poly("room", [(slant(730), 730), (235, 730), (235, 880), (slant(880) - 10, 880)], name="育成中心辦公室"),
        g.room(390, 455, 555, 570, name="企業培育室十"),
        g.room(390, 570, 555, 655, name="企業培育室九"),
        g.room(390, 655, 555, 735, name="企業培育室八"),
        g.room(390, 735, 555, 835, name="會議室"),
        g.poly("room", [(40, 960), (85, 890), (115, 890), (115, 960)], name="設備室"),
        g.rect("elevator", 120, 915, 162, 962),
        g.rect("stairs", 62, 965, 165, 1050),
        g.poly("room", [(165, 880), (490, 880), (490, 945), (320, 945), (320, 1058), (165, 1058)], name="交誼廳"),
        g.rect("restroom", 320, 945, 390, 1055, name="男廁"),
        g.rect("restroom", 425, 945, 490, 1055, name="女廁"),
        g.rect("stairs", 492, 885, 565, 1050),
    ]
    outline = g.pts([(300, 0), (472, 0), (472, 215), (548, 215), (548, 300), (500, 300), (500, 380), (548, 380),
                     (555, 450), (555, 880), (580, 880), (580, 1060), (20, 1060)])
    return {"id": "B1", "outline": outline, "spaces": spaces, "unit": "創新育成中心", "aliases": ["育成中心"]}


def floor_1f():
    g = FIRST

    def r(kind, at, x0, y0, x1, y1, name=None, note=None):
        (u0, v0), (u1, v1) = at(x0, y0), at(x1, y1)
        return g.rect(kind, u0, v0, u1, v1, name=name, note=note)

    def p(kind, at, ps, name=None, note=None):
        return g.poly(kind, [at(*q) for q in ps], name=name, note=note)

    H, L = high, low
    spaces = [
        # The computer centre, east of the long corridor.
        r("stairs", H, 545, 182, 582, 236),
        r("room", H, 585, 145, 645, 236, name="冷氣機房"),
        r("room", H, 650, 145, 815, 236, name="工作室"),
        r("restroom", H, 848, 150, 892, 236, name="無障礙廁所"),
        r("restroom", H, 892, 145, 968, 236, name="女廁"),
        r("restroom", H, 848, 236, 968, 292, name="男廁"),
        r("room", H, 665, 292, 972, 432, name="電腦教室五"),
        r("room", H, 665, 432, 975, 582, name="電腦教室四"),
        r("room", H, 665, 582, 980, 735, name="電腦教室三"),
        r("room", H, 665, 735, 985, 887, name="電腦教室二"),
        r("room", H, 665, 887, 990, 1047, name="電腦教室一", note="雲端自學空間"),
        r("room", L, 665, 135, 995, 300, name="電算中心辦公室"),
        r("room", L, 668, 318, 800, 368, name="服務台"),
        r("elevator", L, 635, 515, 675, 560),
        r("stairs", L, 515, 495, 600, 650),
        # West of the corridor.
        r("room", H, 515, 510, 610, 585, name="工作室"),
        r("room", H, 515, 585, 610, 655, name="工作室"),
        r("room", H, 515, 655, 610, 730, name="工作室"),
        r("room", H, 545, 735, 610, 835, name="影印室"),
        r("room", H, 512, 842, 553, 885, name="茶水間"),
        r("elevator", H, 555, 842, 597, 885),
        r("room", H, 515, 890, 610, 1000, name="數位教材編輯室"),
        # The offices beyond, closed to the public (行政區域).
        p("room", H, [(320, 735), (512, 735), (512, 888), (262, 888)], name="學術網路機房"),
        r("restroom", H, 258, 890, 343, 962, name="教職員女廁"),
        r("restroom", H, 345, 890, 400, 962, name="教職員男廁"),
        r("room", L, 190, 135, 345, 230, name="主任辦公室"),
        r("room", L, 268, 255, 360, 400, name="校務行政資訊中心"),
        r("room", L, 405, 135, 605, 300, name="會議簡報室"),
        r("room", L, 500, 300, 605, 400, name="準備室"),
        r("room", L, 250, 400, 345, 480, name="聯合收發室"),
        r("room", L, 345, 400, 445, 480, name="中央主控室"),
        # The west lobby, under the library's entrance.
        p("room", L, [(185, 485), (510, 485), (510, 652), (185, 652)], name="國際會議廳視聽區及圖書館行政入口大廳"),
        r("elevator", L, 130, 512, 180, 552),
        r("stairs", L, 55, 560, 170, 650),
    ]
    outline = g.pts([H(505, 145), H(975, 145), L(1000, 655), L(17, 655), H(320, 735), H(515, 735), H(515, 410),
                     H(380, 410), H(380, 300), H(505, 300)])
    # As the user outlined them (細節/IMG_6045), along the rooms' walls.
    zones = [
        g.zone([L(110, 400), L(445, 400), L(445, 485), L(510, 485), L(510, 655), L(17, 655)], WING, WING_NOTE,
               entrance=(L(440, 655), (1, 0))),
        g.zone([H(320, 735), H(512, 735), L(512, 88), L(612, 88), L(612, 400), L(110, 400)], "行政區域",
               "不對外開放"),
    ]
    return {"id": "1F", "outline": outline, "spaces": spaces, "zones": zones,
            "unit": "電子計算機中心", "aliases": ["電算中心"]}


def floor_2f():
    g = library((175, 12), (175, 950), (1588, 948), (1588, 465))
    spaces = [
        g.rect("stairs", 195, 40, 270, 165),
        g.rect("elevator", 283, 118, 330, 157),
        g.room(183, 325, 345, 480, name="貴賓室"),
        g.rect("stairs", 190, 485, 345, 555),
        g.rect("elevator", 268, 592, 312, 632),
        g.rect("stairs", 490, 150, 605, 215),
        g.rect("restroom", 485, 240, 585, 325, name="男廁"),
        g.rect("restroom", 485, 330, 585, 425, name="女廁"),
        g.rect("restroom", 530, 428, 580, 475, name="無障礙廁所"),
        # As the user redrew it: down to the lift lobby, round the stair.
        g.poly("room", [(490, 108), (880, 232), (965, 282), (965, 470), (865, 470), (865, 452), (805, 452),
                        (805, 488), (592, 480), (598, 228), (545, 152), (490, 120)], name="演講廳"),
        g.poly("room", [(572, 542), (665, 542), (665, 528), (805, 528), (805, 560), (850, 560), (850, 625),
                        (625, 625), (625, 600), (572, 600)], name="流通櫃臺"),
        g.rect("elevator", 808, 515, 860, 552),
        g.poly("room", [(645, 650), (855, 650), (855, 560), (975, 560), (975, 770), (805, 770), (805, 940),
                        (655, 940), (580, 860), (580, 815), (600, 815), (600, 690), (645, 690)], name="視聽資料區"),
        g.rect("stairs", 810, 778, 938, 940),
        g.room(940, 778, 972, 940, name="閱報區"),
        g.room(975, 482, 1415, 948),
        g.rect("stairs", 1415, 478, 1580, 545),
        g.rect("restroom", 1420, 830, 1580, 940, name="廁所"),
        # The entrance stair down to the road, outside the west wall.
        g.poly("stairs", [(15, 590), (120, 650), (175, 650), (175, 770), (120, 770), (15, 800)]),
    ]
    zones = [g.zone([(175, 12), (345, 69), (345, 322), (175, 322)], WING, WING_NOTE)]
    return {"id": "2F", "outline": LIBRARY, "spaces": spaces, "zones": zones}


def floor_3f():
    g = library((10, 20), (30, 1060), (1595, 1025), (1585, 498))
    spaces = [
        g.rect("stairs", 35, 40, 115, 190),
        g.rect("elevator", 125, 125, 190, 185),
        g.poly("room", [(355, 130), (905, 300), (905, 512), (722, 512), (722, 545), (258, 545), (240, 200),
                        (355, 200)], name="演講廳"),
        g.rect("stairs", 35, 545, 195, 615),
        g.poly("void", [(32, 625), (215, 625), (330, 660), (390, 635), (390, 950), (645, 950), (645, 1052),
                        (32, 1055)]),
        g.poly("room", [(398, 548), (722, 548), (722, 598), (915, 598), (915, 815), (722, 815), (722, 950),
                        (398, 950)], name="黃春明體驗行動館"),
        g.rect("elevator", 740, 555, 785, 595),
        g.rect("stairs", 725, 820, 912, 1030),
        g.poly("room", [(915, 512), (1405, 505), (1405, 588), (1445, 588), (1445, 925), (1405, 925), (1405, 1025),
                        (1025, 1027), (1025, 915), (925, 915), (925, 1028), (915, 1028)], name="學習共享空間"),
        g.room(925, 915, 1025, 1027, name="資訊檢索區"),
        g.rect("stairs", 1405, 500, 1580, 585),
        g.room(1448, 660, 1578, 765, name="314 工作準備室"),
        g.room(1448, 768, 1578, 890, name="313 參考諮詢室"),
        g.rect("restroom", 1410, 925, 1580, 1020, name="廁所"),
    ]
    zones = [g.zone([(10, 20), (912, 298), (910, 512), (722, 512), (722, 545), (10, 545)], WING, WING_NOTE)]
    return {"id": "3F", "outline": LIBRARY, "spaces": spaces, "zones": zones}


def floor_4f():
    g = library((15, 15), (35, 1040), (1590, 1000), (1585, 485))
    spaces = [
        g.rect("stairs", 25, 25, 130, 195),
        g.rect("elevator", 135, 125, 195, 180),
        g.room(192, 85, 287, 195, name="422 圖書管理組"),
        g.room(40, 270, 200, 350, name="418 行政室"),
        g.room(40, 355, 200, 530, name="417 館長室"),
        g.poly("room", [(292, 105), (478, 162), (478, 350), (292, 350)], name="427 採訪工作室"),
        g.poly("room", [(478, 162), (725, 238), (725, 350), (478, 350)], name="428 編目工作室"),
        g.poly("room", [(728, 240), (905, 293), (905, 405), (728, 405)], name="435 期刊工作室"),
        g.room(205, 402, 378, 500, name="424 會議室"),
        g.room(490, 398, 682, 490, name="429 系統資訊室"),
        g.rect("restroom", 735, 440, 778, 490, name="男廁"),
        g.rect("restroom", 782, 440, 848, 490, name="女廁"),
        g.rect("stairs", 35, 535, 210, 610),
        g.poly("room", [(218, 518), (920, 505), (920, 805), (730, 805), (730, 1040), (218, 1040)], name="西文圖書區",
               note="A–Z"),
        g.rect("elevator", 735, 535, 795, 580),
        g.rect("stairs", 730, 805, 925, 1035),
        g.room(40, 620, 215, 1040, name="教職員著作區・學位論文區・課程用書區"),
        g.poly("room", [(920, 500), (1400, 495), (1400, 570), (1440, 570), (1440, 915), (1415, 915), (1415, 1000),
                        (920, 1000)], name="中文圖書區", note="000–369"),
        g.rect("stairs", 1400, 490, 1580, 570),
        g.room(1445, 645, 1580, 745, name="410 工作準備室"),
        g.room(1445, 750, 1580, 860, name="409 檔案室"),
        g.rect("restroom", 1415, 915, 1585, 1000, name="廁所"),
    ]
    zones = [g.zone([(15, 15), (910, 290), (905, 500), (218, 512), (218, 533), (15, 533)], WING, WING_NOTE)]
    return {"id": "4F", "outline": LIBRARY, "spaces": spaces, "zones": zones}


def floor_5f():
    g = library((40, 15), (18, 1045), (1590, 1068), (1588, 545))
    spaces = [
        g.rect("stairs", 55, 25, 140, 185),
        g.rect("elevator", 145, 125, 210, 180),
        g.room(390, 152, 478, 352, name="第二數位攝影棚"),
        g.room(480, 185, 652, 360, name="數位學習資源中心"),
        g.poly("room", [(652, 238), (908, 322), (905, 450), (685, 505), (685, 528), (580, 528), (580, 362),
                        (652, 362)], name="529 視聽室"),
        g.room(358, 422, 580, 528, name="533 會議室"),
        g.rect("stairs", 40, 530, 205, 600),
        g.room(472, 548, 638, 600, name="視聽區"),
        g.rect("elevator", 720, 575, 775, 620),
        g.poly("room", [(375, 600), (638, 600), (638, 548), (905, 548), (905, 845), (700, 845), (700, 975),
                        (372, 975)], name="現期期刊區"),
        *[g.room(x0, 978, x1, 1048, name=f"{n} 宜思智慧小間")
          for n, x0, x1 in ((504, 372, 453), (505, 458, 540), (506, 545, 626))],
        g.rect("stairs", 700, 845, 900, 1045),
        g.poly("room", [(22, 600), (375, 600), (372, 1048), (190, 1048), (190, 905), (22, 905)], name="i 讀書中心"),
        g.room(25, 905, 190, 1040, name="第一數位攝影棚"),
        g.poly("room", [(905, 540), (1410, 540), (1410, 630), (1440, 630), (1440, 975), (1400, 975),
                        (1400, 988), (905, 988)], name="中文圖書區", note="370–449"),
        # Study carrels along the south wall; the sign numbers 510 and 511,
        # the rest follow on.
        *[g.room(1000 + 79 * k, 990, 1072 + 79 * k, 1062, name=f"{507 + k} 研究小間") for k in range(5)],
        g.rect("stairs", 1410, 545, 1588, 630),
        g.room(1440, 705, 1585, 810, name="524 工作準備室"),
        g.room(1440, 815, 1585, 935, name="523 討論室"),
        g.rect("restroom", 1400, 975, 1588, 1065, name="廁所"),
    ]
    zones = [g.zone([(40, 15), (908, 322), (905, 530), (40, 530)], WING, WING_NOTE)]
    return {"id": "5F", "outline": LIBRARY, "spaces": spaces, "zones": zones}


def floor_6f():
    g = library((40, 40), (40, 1055), (1582, 1058), (1578, 522))
    spaces = [
        g.rect("stairs", 52, 48, 150, 210),
        g.rect("elevator", 150, 150, 205, 200),
        g.poly("room", [(208, 96), (540, 203), (540, 537), (208, 537)], name="過期期刊室"),
        g.poly("room", [(553, 206), (898, 318), (898, 465), (720, 465), (720, 537), (553, 537)], name="罕用書典藏庫"),
        g.rect("stairs", 50, 543, 222, 632),
        g.rect("elevator", 725, 578, 775, 620),
        g.rect("stairs", 712, 840, 905, 1050),
        g.poly("room", [(50, 632), (222, 632), (222, 545), (715, 545), (715, 1052), (50, 1052)], name="中文圖書區",
               note="450–782"),
        g.poly("room", [(905, 540), (1405, 540), (1405, 610), (1440, 610), (1440, 960), (1400, 960), (1400, 1052),
                        (905, 1052)], name="中文圖書區", note="782–999"),
        g.rect("stairs", 1405, 528, 1575, 610),
        g.room(1440, 695, 1575, 808, name="613 工作準備室"),
        g.room(1440, 812, 1575, 925, name="612 討論室"),
        g.rect("restroom", 1400, 960, 1575, 1050, name="廁所"),
    ]
    zones = [g.zone([(40, 40), (903, 318), (903, 540), (40, 540)], WING, WING_NOTE)]
    return {"id": "6F", "outline": LIBRARY, "spaces": spaces, "zones": zones}


def floor_7f():
    # West up, north on the right.
    g = Sign([((690, 18), (0, 0)), ((20, 18), (0, NS)), ((20, 1085), (EW, NS)), ((385, 1085), (EW, 23.1))])
    spaces = [
        g.poly("terrace", [(20, 18), (290, 18), (290, 140), (350, 140), (350, 460), (315, 460), (315, 590),
                           (385, 590), (385, 1085), (20, 1085)]),
        g.room(140, 945, 260, 1070, name="空調冷卻水塔"),
        g.rect("stairs", 330, 940, 385, 1085),
        g.rect("stairs", 300, 18, 355, 95),
        g.room(365, 130, 480, 250, name="機房"),
        g.poly("room", [(500, 130), (660, 130), (577, 395), (485, 395), (485, 255), (500, 255)], name="辦公室"),
        g.room(365, 285, 485, 395, name="發電機房"),
        g.poly("room", [(385, 395), (577, 395), (520, 580), (385, 580)], name="機電空間"),
        g.room(318, 470, 358, 545, name="電梯機房"),
        g.room(590, 90, 650, 125, name="電梯機房"),
        g.rect("stairs", 590, 18, 690, 90),
    ]
    outline = g.pts([(20, 18), (690, 18), (660, 128), (520, 580), (385, 580), (385, 1085), (20, 1085)])
    return {"id": "7F", "outline": outline, "spaces": spaces, "unit": "遠傳電信", "aliases": ["遠傳", "FET"]}


def main():
    floors = [f() for f in (floor_b1, floor_1f, floor_2f, floor_3f, floor_4f, floor_5f, floor_6f, floor_7f)]
    building = {"id": "tuzi", "name": "圖書資訊中心（圖書館）", "unit": "m", "floors": floors}
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/tuzi.json", root / "mobile/assets/campus_map/tuzi.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
