#!/usr/bin/env python3
"""Generates app-content/campus-map/tuzi.json (圖書資訊中心).

The library's own floor guides (2F–6F) and 1F's 電算中心, scaled to the
75 × 48 m OpenStreetMap outline. The guides put east up and north on the
left (the slanted wall is the north side; the entrance stair on 2F faces
west), so each is mapped by its outline's box: the guide's bottom edge is
the west wall, its right edge the south wall. The building is shared, but
only the library's floors and 1F's computer centre are mapped so far.
Rooms carry no codes: the library names them, numbers and all (電腦教室一,
523 討論室).
"""
import json
from pathlib import Path

EW, NS = 75.0, 48.0


class Guide:
    """One floor guide: the outline's box in pixels, left, top, right, bottom."""

    def __init__(self, left, top, right, bottom):
        self.l, self.t, self.r, self.b = left, top, right, bottom

    def pt(self, px, py):
        """Pixel to metres east (x) and south (y)."""
        return (round(EW * (self.b - py) / (self.b - self.t), 2),
                round(NS * (px - self.l) / (self.r - self.l), 2))

    def rect(self, kind, px0, py0, px1, py1, code=None, name=None, note=None):
        (xa, ya), (xb, yb) = self.pt(px0, py0), self.pt(px1, py1)
        x0, x1, y0, y1 = min(xa, xb), max(xa, xb), min(ya, yb), max(ya, yb)
        return labelled({"kind": kind, "rect": [x0, y0, round(x1 - x0, 2), round(y1 - y0, 2)]}, code, name, note)

    def poly(self, kind, pts, code=None, name=None, note=None):
        return labelled({"kind": kind, "polygon": [list(self.pt(*p)) for p in pts]}, code, name, note)

    def room(self, *box, code=None, name=None, note=None):
        return self.rect("room", *box, code=code, name=name, note=note)

    def outline(self, pts):
        return [list(self.pt(*p)) for p in pts]


def labelled(space, code, name, note):
    if code:
        space["code"] = code
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


# The library floors' outline in metres: the long south wall, the slanted
# north-west wall, and the narrower east wing.
LIBRARY = [[0, 0], [42.1, 13.1], [42.1, 23.1], [EW, 23.1], [EW, NS], [0, NS]]


def tower(g):
    """Stairs, lifts and toilets 3F, 4F and 6F share, in their guides' pixels."""
    return [
        g.rect("stairs", 378, 20, 440, 150),
        g.rect("restroom", 665, 18, 755, 145, name="廁所"),
        g.rect("elevator", 410, 595, 445, 635),
        g.rect("stairs", 620, 505, 755, 640),
        g.rect("stairs", 392, 1003, 445, 1135),
        g.rect("elevator", 95, 1012, 135, 1052),
        g.rect("stairs", 25, 1062, 140, 1132),
    ]


def floor_1f():
    g = Guide(35, 73, 760, 1140)
    spaces = [
        g.room(435, 82, 488, 118, name="冷氣機房"),
        g.room(435, 118, 488, 158, name="掃具間"),
        g.room(490, 82, 635, 158, name="工作室"),
        g.rect("restroom", 640, 85, 745, 188, name="廁所"),
        g.room(505, 197, 748, 305, name="電腦教室五"),
        g.room(505, 316, 748, 422, name="電腦教室四"),
        g.room(503, 433, 747, 541, name="電腦教室三"),
        g.room(502, 552, 746, 658, name="電腦教室二"),
        g.room(502, 670, 746, 777, name="電腦教室一", note="雲端自學空間"),
        g.room(502, 783, 746, 890, name="電算中心辦公室"),
        g.room(503, 893, 613, 928, name="服務台"),
        g.room(380, 375, 460, 430, name="工作室"),
        g.room(380, 435, 460, 490, name="工作室"),
        g.room(380, 495, 460, 542, name="工作室"),
        g.room(380, 545, 460, 585, name="影印室"),
        g.room(377, 590, 460, 638, name="茶水間"),
        g.room(377, 642, 460, 732, name="數位教材編輯室"),
        g.poly("room", [(220, 548), (375, 548), (375, 732), (290, 732), (290, 658), (188, 658)], name="學術網路機房"),
        g.rect("restroom", 165, 658, 245, 732, name="女廁"),
        g.rect("restroom", 245, 658, 290, 732, name="男廁"),
        g.room(150, 735, 222, 778, name="小型會議室"),
        g.room(125, 780, 222, 840, name="系統組"),
        g.poly("room", [(105, 843), (188, 843), (188, 953), (80, 953)], name="網路組"),
        g.room(188, 870, 255, 953, name="行政機房"),
        g.room(300, 780, 458, 898, name="會議室"),
        g.poly("room", [(258, 840), (300, 840), (300, 900), (458, 900), (458, 953), (258, 953)], name="儲物室"),
        g.rect("stairs", 40, 1060, 135, 1135),
        g.rect("stairs", 380, 1015, 495, 1135),
    ]
    outline = g.outline([(432, 73), (760, 73), (760, 900), (688, 900), (688, 1015), (495, 1015), (495, 1140),
                         (35, 1140), (35, 1060), (70, 1060), (70, 960), (218, 543), (380, 543), (380, 300),
                         (432, 300)])
    return {"id": "1F", "outline": outline, "spaces": spaces, "unit": "電子計算機中心", "aliases": ["電算中心"]}


def floor_2f():
    g = Guide(0, 12, 1212, 1815)
    spaces = [
        g.rect("stairs", 612, 52, 688, 240),
        g.rect("restroom", 1040, 55, 1172, 240, name="廁所"),
        g.room(612, 240, 1172, 780, name="宜大記憶庫"),
        g.rect("stairs", 975, 808, 1170, 1020),
        g.rect("elevator", 645, 945, 698, 1018),
        g.room(665, 965, 860, 1240, name="流通櫃臺"),
        g.poly("room", [(1027, 1025), (1170, 1025), (1170, 1210), (1085, 1295), (1027, 1295)], name="閱報區"),
        g.room(682, 1198, 772, 1298, name="辦公室"),
        g.poly("room", [(340, 830), (610, 830), (605, 1290), (160, 1410)], name="演講廳"),
        g.rect("stairs", 190, 1265, 305, 1420),
        g.rect("restroom", 307, 1295, 412, 1418, name="男廁"),
        g.rect("restroom", 417, 1295, 530, 1418, name="女廁"),
        g.rect("restroom", 538, 1295, 600, 1365, name="無障礙廁所"),
        g.room(178, 1432, 602, 1582, name="陳忠藏作品展示區"),
        g.room(415, 1590, 605, 1775, name="貴賓室"),
        g.rect("elevator", 148, 1600, 210, 1670),
        g.rect("stairs", 80, 1680, 225, 1775),
        g.rect("stairs", 615, 1590, 697, 1775),
        g.rect("elevator", 745, 1625, 795, 1680),
        g.rect("void", 990, 1295, 1172, 1590),
    ]
    return {"id": "2F", "outline": LIBRARY, "spaces": spaces}


def floor_3f():
    g = Guide(15, 14, 760, 1142)
    spaces = [
        *tower(g),
        g.room(380, 150, 755, 505, name="學習共享空間"),
        g.poly("room", [(460, 505), (618, 505), (618, 648), (755, 648), (755, 700), (688, 700), (688, 880),
                        (398, 880), (398, 648), (460, 648)], name="黃春明體驗行動館"),
        g.poly("room", [(222, 515), (390, 515), (390, 972), (98, 895)], name="演講廳"),
        g.rect("void", 450, 880, 755, 1140),
    ]
    return {"id": "3F", "outline": LIBRARY, "spaces": spaces}


def floor_4f():
    g = Guide(15, 12, 765, 1140)
    spaces = [
        *tower(g),
        g.room(490, 18, 568, 112, name="工作準備室"),
        g.room(568, 18, 665, 112, name="檔案室"),
        g.room(380, 145, 755, 495, name="西文圖書區"),
        g.room(380, 645, 755, 995, name="西文圖書區"),
        g.room(452, 1005, 755, 1125, name="課程用書區・教職員著作區・學位論文區"),
        g.room(260, 1012, 388, 1125, name="館長室"),
        g.room(200, 1012, 260, 1125, name="行政室"),
        g.room(297, 888, 377, 1005, name="會議室"),
        g.room(297, 672, 377, 808, name="系統資訊室"),
        g.rect("restroom", 332, 552, 377, 590, name="女廁"),
        g.rect("restroom", 332, 592, 377, 632, name="男廁"),
        g.poly("room", [(218, 515), (312, 515), (312, 638), (176, 638)], name="期刊工作室"),
        g.poly("room", [(176, 640), (262, 640), (262, 810), (122, 810)], name="編目工作室"),
        g.poly("room", [(122, 810), (262, 810), (262, 945), (80, 945)], name="採訪工作室"),
        g.poly("room", [(80, 950), (140, 950), (140, 1008), (62, 1008)], name="圖書管理組"),
    ]
    return {"id": "4F", "outline": LIBRARY, "spaces": spaces}


def floor_5f():
    g = Guide(20, 14, 1100, 1670)
    spaces = [
        g.rect("stairs", 555, 30, 630, 200),
        g.room(705, 30, 820, 165, name="工作準備室"),
        g.room(820, 30, 965, 165, name="523 討論室"),
        g.rect("restroom", 965, 30, 1085, 215, name="廁所"),
        g.room(550, 165, 1000, 725, name="中文圖書區"),
        # Study carrels: the guide numbers 511, 510 and 506–504; the rest
        # follow on.
        *[g.room(1005, 215 + 83 * k, 1085, 298 + 83 * k, name=f"{511 - k} 研究小間") for k in range(5)],
        g.rect("stairs", 870, 745, 1090, 945),
        g.rect("elevator", 590, 870, 635, 935),
        g.room(560, 950, 990, 1295, name="現期期刊區"),
        *[g.room(992, 1020 + 90 * k, 1085, 1110 + 90 * k, name=f"{506 - k} 宜思菁華小間") for k in range(3)],
        g.poly("room", [(320, 760), (455, 760), (545, 985), (430, 1020), (430, 1235), (360, 1240), (360, 1295),
                        (140, 1295)], name="數位學習資源中心"),
        g.room(550, 1300, 1090, 1670, name="I 讀書中心"),
        g.rect("elevator", 130, 1490, 180, 1550),
        g.rect("stairs", 55, 1560, 185, 1660),
        g.rect("stairs", 555, 1500, 630, 1665),
    ]
    return {"id": "5F", "outline": LIBRARY, "spaces": spaces}


def floor_6f():
    g = Guide(15, 14, 760, 1142)
    spaces = [
        *tower(g),
        g.room(488, 25, 565, 118, name="工作準備室"),
        g.room(567, 25, 660, 118, name="612 討論室"),
        g.room(380, 150, 750, 505, name="中文圖書區"),
        g.room(385, 648, 750, 1130, name="中文圖書區"),
        g.poly("room", [(222, 518), (325, 518), (325, 645), (378, 645), (378, 765), (148, 765)], name="罕用書區"),
        g.poly("room", [(140, 775), (378, 775), (378, 1008), (66, 1008)], name="過期期刊區"),
    ]
    return {"id": "6F", "outline": LIBRARY, "spaces": spaces}


def main():
    floors = [f() for f in (floor_1f, floor_2f, floor_3f, floor_4f, floor_5f, floor_6f)]
    building = {"id": "tuzi", "name": "圖書資訊中心（圖書館）", "unit": "m", "floors": floors}
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/tuzi.json", root / "mobile/assets/campus_map/tuzi.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
