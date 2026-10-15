#!/usr/bin/env python3
"""Generates app-content/campus-map/tiyu.json (體育館).

Five floors from the emergency route maps by each floor's stairs, each
fitted by four corners to the 76 × 76 m OpenStreetMap outline, which also
takes out the camera's slant. No sign is north up: B1, 1F and 4F put north
on the right and east down; 2F and 3F are drawn upside down, south up and
west on the right. The small notch at the north-east corner, where the
outdoor steps climb to the 2F stands, and the stair towers on the west
and north walls fix which way each sign is turned.

The south-west half is the hall: B1's 網球、羽球、排球區 rises through 1F
(drawn as `void` there), the 2F court is the floor above it and is open to
the roof, so 3F's 室內跑道 rings a `void` and 4F looks down on it too. The
2F stands, stepped and unnamed on the sign, are a terrace. 5F (永續發展中心
on the directory) has no sign and is left out.

Rooms carry no codes: the emergency maps have none, and the directories'
four-digit numbers (0314, 9919 …) go in `aka` where the directory's name
matches the room on the map. 4F is 建築與永續規劃研究所.
"""
import json
from pathlib import Path

EW, NS = 76.2, 76.1


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
    """One photographed sign: four pixel points (in a 1600-px-long
    thumbnail of the photo) and where they are in metres (east, south), as a
    projective map."""

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


def north_right(nw, ne, se, sw):
    """B1, 1F, 4F: north on the right, east down. The corners are the sign's
    top right, bottom right (where the walls would meet without the notch),
    bottom left and top left."""
    return Sign([(nw, (0, 0)), (ne, (EW, 0)), (se, (EW, NS)), (sw, (0, NS))])


def south_up(nw, ne, se, sw):
    """2F, 3F: upside down, south up. Corners: the sign's bottom right,
    bottom left, top left and top right."""
    return Sign([(nw, (0, 0)), (ne, (EW, 0)), (se, (EW, NS)), (sw, (0, NS))])


class View:
    """A zoomed crop of one sign: pixels in the crop, from its corner at
    (ox, oy) in the thumbnail, magnified z times."""

    def __init__(self, sign, ox, oy, z):
        self.g, self.ox, self.oy, self.z = sign, ox, oy, z

    def at(self, x, y):
        return self.ox + x / self.z, self.oy + y / self.z

    def pts(self, ps):
        return self.g.pts([self.at(*p) for p in ps])

    def poly(self, kind, ps, name=None, aka=None, note=None):
        return labelled({"kind": kind, "polygon": self.pts(ps)}, name, aka, note)

    def rect(self, kind, x0, y0, x1, y1, name=None, aka=None, note=None):
        ps = self.pts([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
        xs, ys = [p[0] for p in ps], [p[1] for p in ps]
        area = abs(sum(p[0] * q[1] - q[0] * p[1] for p, q in zip(ps, ps[1:] + ps[:1]))) / 2
        lx, ly = min(xs), min(ys)
        if area > .96 * (max(xs) - lx) * (max(ys) - ly):
            space = {"kind": kind, "rect": [lx, ly, round(max(xs) - lx, 2), round(max(ys) - ly, 2)]}
        else:
            space = {"kind": kind, "polygon": ps}
        return labelled(space, name, aka, note)

    def room(self, *box, name=None, aka=None, note=None):
        return self.rect("room", *box, name=name, aka=aka, note=note)

    def wc(self, *box, name, aka=None):
        return self.rect("restroom", *box, name=name, aka=aka)


def labelled(space, name, aka, note):
    if name:
        space["name"] = name
    if aka:
        space["aka"] = aka
    if note:
        space["note"] = note
    return space


def floor_b1():
    g = north_right((906, 604), (902, 1262), (260, 1262), (275, 602))
    nw, ne = View(g, 230, 560, 2.4), View(g, 600, 560, 2.4)
    sw, se = View(g, 230, 900, 2.4), View(g, 600, 900, 2.4)
    t = View(g, 0, 0, 1)  # the thumbnail itself
    spaces = [
        t.rect("corridor", 318, 602, 904, 643),
        t.rect("corridor", 277, 643, 318, 1092),
        t.rect("corridor", 630, 643, 645, 1140),
        se.rect("corridor", 96, 340, 160, 615),
        sw.rect("corridor", 175, 575, 1050, 615),
        sw.rect("corridor", 175, 815, 950, 870),
        nw.rect("stairs", 135, 30, 205, 195),
        ne.rect("stairs", 255, 45, 330, 190),
        ne.rect("stairs", 590, 50, 660, 215),
        t.room(320, 643, 630, 1092, name="網球、羽球、排球區", aka=["9919", "羽球場", "排球場"]),
        t.room(645, 648, 904, 1042, name="撞球、桌球區", aka=["9922", "桌球室"]),
        ne.rect("stairs", 160, 650, 340, 800),
        sw.room(100, 330, 175, 460, name="泵浦室", aka=["9917"]),
        sw.rect("stairs", 20, 670, 130, 745),
        sw.rect("terrace", 70, 780, 175, 860, name="天井"),
        sw.room(235, 465, 330, 575, name="女更衣室", aka=["9904"]),
        sw.room(330, 465, 430, 575, name="女淋浴間", aka=["9905"]),
        sw.wc(430, 465, 555, 575, name="女廁", aka=["9906"]),
        sw.wc(555, 465, 735, 575, name="男廁", aka=["9907"]),
        sw.room(735, 465, 830, 575, name="男淋浴間", aka=["9908"]),
        sw.room(830, 465, 984, 575, name="男更衣室", aka=["9909"]),
        sw.room(220, 615, 950, 815, name="重量訓練室"),
        se.wc(160, 345, 240, 480, name="男廁", aka=["9914"]),
        se.wc(240, 345, 320, 480, name="女廁", aka=["9914-2"]),
        se.rect("elevator", 240, 490, 300, 545),
        se.rect("stairs", 240, 560, 320, 700),
        se.room(320, 350, 500, 770, name="菓嶺教室", aka=["果嶺教室"]),
        se.room(500, 355, 725, 490, name="空調主機房", aka=["9916-2"]),
        se.poly("room", [(60, 610), (240, 610), (240, 700), (320, 700), (320, 862), (60, 862)], name="多用途空間"),
    ]
    outline = t.pts([(275, 602), (906, 604), (902, 1225), (733, 1225), (733, 1262), (260, 1262)])
    return {"id": "B1", "outline": outline, "spaces": spaces}


def floor_1f():
    g = north_right((1360, 303), (1366, 1042), (658, 1046), (655, 308))
    nw, ne = View(g, 600, 250, 2.4), View(g, 990, 250, 2.4)
    sw, se = View(g, 600, 640, 2.4), View(g, 990, 640, 2.4)
    t = View(g, 0, 0, 1)
    spaces = [
        t.rect("corridor", 685, 308, 1360, 354),
        t.rect("corridor", 655, 354, 702, 857),
        t.rect("corridor", 1052, 354, 1092, 900),
        t.rect("corridor", 1092, 354, 1360, 732),
        sw.rect("corridor", 140, 615, 1217, 685),
        sw.rect("corridor", 140, 640, 245, 760),
        # B1's hall, two storeys high.
        t.rect("void", 702, 354, 1052, 857),
        nw.rect("stairs", 125, 70, 205, 250),
        ne.rect("stairs", 320, 40, 400, 245),
        ne.rect("stairs", 725, 40, 805, 245),
        ne.wc(220, 320, 300, 480, name="男廁"),
        ne.wc(300, 320, 415, 450, name="女廁"),
        ne.room(245, 480, 430, 740, name="運動傷害防護室"),
        ne.rect("void", 485, 450, 650, 690),
        ne.room(700, 300, 880, 740, name="體育組", aka=["體育教師辦公室"]),
        ne.rect("stairs", 330, 740, 440, 920),
        se.room(260, 280, 450, 520, name="器材室"),
        se.room(450, 225, 710, 600, name="視聽室"),
        se.room(710, 280, 900, 600, name="體適能中心"),
        se.rect("elevator", 355, 535, 425, 605),
        se.rect("stairs", 355, 620, 445, 760),
        se.room(100, 680, 185, 740, name="管理員室"),
        se.room(100, 750, 185, 890, name="器材室"),
        sw.room(140, 525, 245, 640, name="器材室"),
        sw.room(245, 520, 405, 615, name="更衣室"),
        sw.room(405, 520, 515, 615, name="淋浴間"),
        sw.wc(515, 520, 657, 615, name="女廁"),
        sw.wc(657, 520, 850, 615, name="男廁"),
        sw.room(850, 520, 945, 615, name="淋浴間"),
        se.room(0, 510, 150, 600, name="更衣室"),
        sw.rect("stairs", 60, 760, 200, 850),
        sw.room(140, 860, 245, 975, name="空調室"),
        sw.poly("room", [(250, 685), (1035, 685), (1035, 910), (250, 910)], name="韻律舞蹈室", aka=["韻律活動室"]),
    ]
    outline = t.pts([(655, 308), (1360, 303), (1362, 890), (1184, 890), (1184, 1044), (658, 1046)])
    return {"id": "1F", "outline": outline, "spaces": spaces}


def floor_2f():
    g = south_up((1262, 943), (556, 943), (556, 266), (1262, 266))
    nw, ne = View(g, 540, 230, 2.5), View(g, 900, 230, 2.5)
    sw, se = View(g, 540, 600, 2.5), View(g, 900, 600, 2.5)
    t = View(g, 0, 0, 1)
    spaces = [
        t.rect("corridor", 580, 308, 1220, 346),
        t.rect("corridor", 556, 308, 580, 590),
        t.rect("corridor", 1192, 346, 1220, 943),
        t.rect("corridor", 708, 346, 736, 640),
        t.rect("corridor", 608, 640, 1220, 684),
        t.rect("corridor", 848, 684, 960, 943),
        se.rect("corridor", 0, 410, 800, 455),
        se.rect("corridor", 0, 610, 800, 660),
        nw.room(40, 95, 155, 195, name="空調室"),
        nw.rect("stairs", 160, 0, 245, 190),
        nw.room(315, 95, 475, 200, name="空調室"),
        nw.room(100, 250, 320, 900, name="有氧舞蹈室"),
        nw.poly("room", [(320, 250), (465, 250), (435, 330), (350, 345), (320, 340)], name="音控室"),
        nw.poly("room", [(320, 345), (435, 330), (470, 600), (440, 910), (320, 910)], name="舞台"),
        t.room(736, 348, 1192, 612, name="籃球場兼排球、網球場", aka=["籃球場兼網球場", "籃球場", "排球場", "網球場"]),
        ne.room(805, 190, 900, 320, name="空調室"),
        ne.rect("stairs", 850, 85, 990, 185),
        sw.wc(45, -20, 170, 55, name="男廁"),
        sw.wc(215, -20, 320, 55, name="女廁"),
        nw.wc(355, 905, 440, 975, name="廁所"),
        sw.room(45, 55, 165, 140, name="觀察休養及哺乳室"),
        sw.room(215, 55, 325, 140, name="健康咨詢及哺乳室", aka=["健康諮詢及哺乳室"]),
        sw.poly("room", [(325, 40), (445, 40), (475, 135), (325, 135)], name="貴賓室"),
        sw.room(140, 140, 400, 300, name="掛號候診區"),
        sw.room(45, 220, 140, 310, name="自助診察室"),
        sw.room(45, 310, 165, 405, name="內科診察室"),
        sw.room(190, 300, 245, 405, name="藥品室"),
        sw.rect("stairs", 245, 315, 345, 405),
        sw.rect("elevator", 400, 315, 470, 395),
        sw.room(475, 310, 620, 405, name="電腦及資料室"),
        sw.room(620, 215, 770, 405, name="衛生保健組辦公室"),
        # The stands, stepped down to the north-east corner.
        sw.rect("terrace", 140, 405, 620, 855),
        sw.rect("stairs", 700, 655, 780, 855),
        se.rect("stairs", 150, 210, 290, 410),
        se.room(300, 210, 595, 410, name="職涯發展中心", aka=["就業輔導組", "行政會議室"]),
        se.room(595, 215, 650, 410, name="學籍檔案室"),
        se.wc(650, 245, 735, 315, name="女廁"),
        se.wc(650, 315, 735, 410, name="男廁"),
        se.room(150, 455, 300, 540, name="儲藏室"),
        se.room(150, 540, 300, 610, name="課務組試務中心"),
        se.rect("void", 345, 455, 590, 615),
        se.room(635, 455, 800, 615, name="永齡基金會"),
        se.poly("room", [(55, 660), (445, 660), (445, 715), (370, 715), (370, 855), (55, 855)], name="生活輔導組辦公室"),
        se.room(370, 715, 445, 855, name="儲藏室"),
        se.room(445, 660, 595, 855, name="軍訓室"),
        se.room(595, 660, 735, 855, name="軍訓室主任室"),
        se.room(735, 765, 800, 855, name="倉庫"),
        se.room(800, 0, 900, 120, name="空調室"),
        se.rect("stairs", 840, 290, 995, 385),
        se.rect("stairs", 840, 700, 995, 790),
    ]
    outline = t.pts([(556, 266), (1262, 266), (1262, 943), (596, 943), (596, 760), (556, 760)])
    return {"id": "2F", "outline": outline, "spaces": spaces}


def floor_3f():
    g = south_up((1258, 898), (569, 898), (566, 210), (1282, 212))
    nw, ne = View(g, 550, 170, 2.5), View(g, 920, 170, 2.5)
    sw, se = View(g, 550, 470, 2.5), View(g, 900, 600, 2.5)
    t = View(g, 0, 0, 1)
    track = {"name": "室內跑道", "aka": ["0303"]}
    spaces = [
        # The track around the court's open space; each straight carries the
        # name, as a ring's middle would fall in the void.
        t.room(616, 218, 1280, 290, **track),
        t.room(616, 585, 1280, 642, **track),
        t.room(568, 250, 672, 585, **track),
        t.room(1208, 290, 1280, 585, **track),
        t.rect("void", 672, 290, 1208, 585),
        t.rect("corridor", 616, 642, 1265, 670),
        se.rect("corridor", 0, 120, 160, 745),
        se.rect("corridor", 160, 300, 800, 355),
        se.rect("corridor", 160, 520, 760, 555),
        se.rect("corridor", 595, 300, 640, 555),
        se.rect("corridor", 750, 120, 800, 745),
        nw.room(40, 100, 165, 200, name="空調室", aka=["0301"]),
        nw.rect("stairs", 165, 20, 245, 110),
        ne.rect("stairs", 820, 100, 990, 190),
        sw.room(45, 330, 165, 430, name="空調室", aka=["0304"]),
        sw.rect("terrace", 45, 440, 165, 610, name="露台"),
        sw.wc(200, 490, 320, 530, name="男廁", aka=["0307"]),
        sw.wc(165, 530, 265, 610, name="女廁", aka=["0306"]),
        sw.rect("stairs", 265, 530, 360, 610),
        sw.rect("elevator", 395, 515, 465, 570),
        sw.room(470, 500, 680, 605, name="學務長辦公室", aka=["0311"]),
        sw.room(680, 500, 760, 605, name="茶水間"),
        sw.room(760, 500, 900, 605, name="會議室", aka=["0314"]),
        sw.rect("stairs", 610, 870, 890, 1050),
        se.rect("stairs", 160, 180, 290, 290),
        se.room(305, 185, 600, 300, name="健康教育室"),
        se.wc(600, 185, 660, 300, name="男廁", aka=["0315"]),
        se.wc(660, 185, 755, 320, name="女廁", aka=["0316"]),
        se.room(160, 300, 300, 385, name="義工團體室"),
        se.room(160, 385, 300, 470, name="心理測驗室"),
        se.room(160, 470, 300, 550, name="團體輔導室"),
        se.rect("void", 355, 355, 595, 520),
        se.room(640, 360, 750, 520, name="圖書室"),
        se.rect("terrace", 830, 330, 910, 560, name="花園"),
        se.rect("terrace", 800, 120, 905, 180, name="小陽台"),
        se.rect("terrace", 800, 690, 905, 745, name="小陽台"),
        se.rect("stairs", 820, 200, 1000, 290),
        se.rect("stairs", 820, 610, 1000, 690),
        se.room(160, 555, 445, 745, name="研習室"),
        se.room(445, 555, 520, 645, name="個別諮商室"),
        se.room(445, 645, 520, 745, name="輔導老師辦公室"),
        se.room(520, 555, 670, 745, name="學生諮商中心辦公室"),
        se.room(670, 555, 740, 745, name="學生諮商中心主任辦公室"),
    ]
    outline = t.pts([(566, 210), (1282, 212), (1258, 898), (794, 898), (794, 715), (568, 714)])
    return {"id": "3F", "outline": outline, "spaces": spaces}


UNIT = "建築與永續規劃研究所"


def floor_4f():
    g = north_right((1137, 312), (1137, 1445), (50, 1445), (52, 312))
    n, m = View(g, 680, 250, 2), View(g, 680, 690, 2)
    w, s = View(g, 0, 1150, 2), View(g, 500, 1100, 2)
    t = View(g, 0, 0, 1)
    spaces = [
        t.rect("corridor", 680, 382, 1137, 420),
        t.rect("corridor", 680, 420, 732, 1265),
        t.rect("corridor", 80, 1315, 137, 1370),
        t.rect("corridor", 137, 1337, 735, 1367),
        t.rect("corridor", 677, 1265, 735, 1445),
        n.rect("corridor", 355, 340, 415, 900),
        n.rect("corridor", 620, 340, 690, 900),
        n.rect("corridor", 110, 845, 690, 900),
        s.rect("corridor", 470, 220, 600, 340),
        # The hall's open space, over the 2F court.
        t.rect("void", 52, 312, 680, 1265),
        n.rect("terrace", 105, 140, 210, 265, name="露台"),
        n.rect("stairs", 210, 20, 320, 265),
        n.room(320, 140, 395, 265, name="儲存室"),
        n.room(395, 100, 635, 265, name="交誼廳"),
        n.room(635, 140, 720, 265, name="儲存室"),
        n.rect("stairs", 720, 20, 820, 265),
        n.rect("terrace", 820, 140, 910, 265, name="露台"),
        n.wc(110, 340, 195, 530, name="女廁"),
        n.wc(195, 340, 355, 530, name="男廁"),
        n.room(110, 540, 355, 845, name="設計工作室、建築模型工作室", note=UNIT),
        n.room(415, 340, 620, 470, name="空間資訊實驗室", note=UNIT),
        n.rect("void", 415, 525, 610, 840),
        n.room(690, 350, 910, 535, name="教學討論室"),
        n.room(690, 535, 910, 715, name="研究生研討室", note=UNIT),
        t.room(1025, 607, 1137, 792, name="多媒體視聽室"),
        m.rect("stairs", 220, 50, 330, 205),
        m.room(105, 205, 350, 390, name="公共空間"),
        m.room(355, 15, 690, 210, name="多功能會議室"),
        m.rect("void", 355, 210, 690, 580),
        m.rect("void", 690, 390, 915, 580),
        m.room(105, 390, 350, 575, name="教學討論室"),
        m.room(105, 575, 350, 760, name="所長辦公室", note=UNIT),
        m.room(105, 760, 350, 940, name="所辦及圖書室", note=UNIT),
        s.rect("elevator", 595, 140, 665, 220),
        s.rect("stairs", 595, 260, 700, 430),
        s.room(470, 340, 595, 435, name="連絡室"),
        s.rect("terrace", 470, 435, 720, 530, name="陽台"),
        w.room(100, 230, 275, 330, name="辦公室"),
        w.rect("stairs", 0, 330, 160, 430),
        w.room(100, 440, 275, 590, name="辦公室"),
    ]
    edges = [137, 207, 302, 397, 490, 582, 677]
    for a, b in zip(edges, edges[1:]):
        spaces.append(t.room(a, 1265, b, 1337, name="辦公室"))
        spaces.append(t.room(a, 1367, b, 1445, name="辦公室"))
    outline = t.pts([(52, 312), (1137, 312), (1137, 1075), (860, 1075), (860, 1368), (745, 1368), (745, 1445),
                     (50, 1445)])
    return {"id": "4F", "outline": outline, "spaces": spaces, "unit": UNIT, "aliases": ["建築所", "建築", "永續規劃"]}


def main():
    floors = [f() for f in (floor_b1, floor_1f, floor_2f, floor_3f, floor_4f)]
    building = {"id": "tiyu", "name": "體育館", "unit": "m", "floors": floors}
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/tiyu.json", root / "mobile/assets/campus_map/tiyu.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
