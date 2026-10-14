#!/usr/bin/env python3
"""Generates app-content/campus-map/gezhi.json (格致大樓, 電資學院).

Measured from the departments' coloured floor directories (2F–6F) and the
1F accessibility map, each photographed at an angle: every sign's outer
corners are mapped to the building, then to the 43 × 53 m OpenStreetMap
outline. The signs put the main stairs on top; that side is west (the 1F
sign's 馬路 is 南大路 to the north, and the 2F walkway at the top of the
left wing meets 電資二館's bridge), so plans turn a quarter round to north
up: a C open to the east around a courtyard.

Codes: students use the 電 numbers the user wrote on the signs; the signs'
own E (2F–6F) and 格 (1F) numbers are still used by the school, so they stay
searchable as `aka`. A room the user didn't number keeps its sign number.
"""
import json
from pathlib import Path

EW, NS = 43.0, 53.0  # metres: the signs' height runs west→east, width south→north


def homography(src, dst):
    def solve(a, b):
        n = len(b)
        m = [row[:] + [b[i]] for i, row in enumerate(a)]
        for c in range(n):
            p = max(range(c, n), key=lambda r: abs(m[r][c]))
            m[c], m[p] = m[p], m[c]
            for r in range(n):
                if r != c:
                    f = m[r][c] / m[c][c]
                    m[r] = [x - f * y for x, y in zip(m[r], m[c])]
        return [m[i][n] / m[i][i] for i in range(n)]

    a, b = [], []
    for (x, y), (u, v) in zip(src, dst):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    h = solve(a, b)
    return lambda x, y: ((h[0] * x + h[1] * y + h[2]) / (h[6] * x + h[7] * y + 1),
                         (h[3] * x + h[4] * y + h[5]) / (h[6] * x + h[7] * y + 1))


def to_metres(s, t):
    """Sign fraction (s right, t down) to metres east (x) and south (y)."""
    return round(t * EW, 2), round((1 - s) * NS, 2)


class Sign:
    """One photographed sign: its outer corners TL, TR, BR, BL in pixels."""

    def __init__(self, corners):
        self.f = homography(corners, [(0, 0), (1, 0), (1, 1), (0, 1)])

    def pt(self, x, y):
        return to_metres(*self.f(x, y))

    def rect(self, kind, box, code=None, name=None, aka=None, note=None):
        x0, y0, x1, y1 = box
        pts = [self.pt(x0, y0), self.pt(x1, y0), self.pt(x1, y1), self.pt(x0, y1)]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        a, b, c, d = min(xs), min(ys), max(xs), max(ys)
        return labelled({"kind": kind, "rect": [a, b, round(c - a, 2), round(d - b, 2)]}, code, name, aka, note)

    def poly(self, kind, pts, code=None, name=None, aka=None, note=None):
        return labelled({"kind": kind, "polygon": [list(self.pt(*p)) for p in pts]}, code, name, aka, note)


def labelled(space, code, name, aka, note):
    if code:
        space["code"] = code
    if aka and aka != code:
        space["aka"] = [aka]
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


def numbered(sign, box, ours, theirs, name=None, note=None, kind="room"):
    """A room the user numbered 電`ours` (None if not) on a sign that calls
    it `theirs`."""
    code = f"電{ours}" if ours else theirs
    return sign.rect(kind, box, code, name, theirs, note)


# The building's outline in sign fractions (s, t): the C and the stair
# block on the west, then turned to metres.
OUTLINE = [to_metres(s, t) for s, t in [
    (0, 0), (0.317, 0), (0.317, -0.13), (0.518, -0.13), (0.518, 0), (1, 0), (1, 1),
    (0.6, 1), (0.6, 0.46), (0.235, 0.46), (0.235, 1), (0, 1),
]]


def floor(level, spaces, unit=None, aliases=(), links=()):
    plan = {"id": level, "outline": [list(p) for p in OUTLINE], "spaces": spaces}
    if unit:
        plan["unit"] = unit
        plan["aliases"] = list(aliases)
        for s in spaces:
            if s.get("name") and any(w in s["name"] for w in ("系辦公室", "系主任", "系會議室", "系學會")) \
                    and "note" not in s and unit not in s["name"]:
                s["note"] = unit
    if links:
        plan["links"] = list(links)
    return plan


def core(sign, stairs, lobby, lift, toilets):
    """The west stair block, lobby, lift and toilets every floor shares."""
    out = [sign.rect("stairs", stairs), sign.rect("corridor", lobby), sign.rect("elevator", lift)]
    for box, name in toilets:
        out.append(sign.rect("restroom", box, name=name))
    return out


def floor_1f():
    s = Sign([(555, 155), (1645, 145), (1645, 855), (565, 865)])
    spaces = [
        s.rect("corridor", (770, 395, 1500, 465)),
        s.rect("corridor", (770, 465, 805, 860)),
        s.rect("corridor", (1250, 465, 1280, 860)),
        s.rect("corridor", (1485, 465, 1640, 615)),
        s.rect("corridor", (920, 155, 1120, 435)),
        s.rect("stairs", (920, 75, 1115, 155)),
        s.rect("stairs", (950, 175, 1080, 260)),
        s.rect("elevator", (985, 270, 1060, 335)),
        s.rect("restroom", (1120, 155, 1200, 315), name="女廁"),
        s.rect("restroom", (1200, 155, 1275, 315), name="男廁"),
        s.rect("restroom", (1195, 315, 1275, 395), name="無障礙廁所"),
        s.rect("restroom", (845, 280, 920, 395), name="無障礙廁所"),
        numbered(s, (560, 160, 765, 470), 111, "格106", "電工儀表實驗室"),
        numbered(s, (565, 470, 770, 785), 112, "格107", "基本電子實驗室"),
        s.rect("room", (575, 785, 675, 865), name="材料室"),
        numbered(s, (675, 785, 770, 865), 113, None, "研究室"),
        s.rect("room", (765, 160, 840, 275), name="材料室"),
        numbered(s, (840, 160, 920, 280), 109, "格104", "材料室"),
        numbered(s, (765, 275, 845, 395), 110, "格105", "研究室"),
        numbered(s, (1280, 150, 1380, 230), None, "格103-1", "研究室"),
        numbered(s, (1380, 150, 1480, 230), 104, "格103-2", "研究室"),
        numbered(s, (1545, 150, 1640, 225), 105, "格103-3", "研究室"),
        numbered(s, (1545, 225, 1640, 305), 106, "格103-4", "研究室"),
        numbered(s, (1545, 305, 1640, 385), 107, "格103-5", "研究室"),
        s.poly("room", [(1280, 230), (1480, 230), (1480, 150), (1545, 150), (1545, 385), (1280, 385)],
               "電108", "高壓電機檢驗實驗室", "格103"),
        numbered(s, (1280, 465, 1375, 540), 102, "格101", "材料室"),
        s.rect("room", (1375, 465, 1485, 540), "格101", "材料室"),
        numbered(s, (1280, 540, 1485, 855), 101, "格101", "電機機械電力電子實驗室"),
        numbered(s, (1485, 615, 1640, 855), 103, None),
    ]
    return floor("1F", spaces)


def floor_2f():
    s = Sign([(130, 218), (1915, 218), (1915, 1345), (130, 1345)])
    spaces = [
        s.rect("corridor", (150, 655, 1290, 740)),
        s.rect("corridor", (585, 600, 1170, 655)),
        s.rect("corridor", (470, 740, 545, 1290)),
        s.rect("corridor", (180, 1160, 475, 1215)),
        s.rect("corridor", (1200, 740, 1290, 1290)),
        s.rect("corridor", (1290, 1000, 1615, 1110)),
        s.rect("corridor", (1600, 1060, 1660, 1255)),
        s.rect("corridor", (1650, 218, 1735, 630)),
        *core(s, (695, 75, 1055, 355), (715, 355, 1040, 600), (815, 405, 935, 525),
              [((585, 218, 700, 460), "男廁"), ((620, 470, 715, 565), "男廁"),
               ((1040, 218, 1170, 490), "女廁"), ((1040, 495, 1135, 575), "親子廁所")]),
        numbered(s, (130, 218, 295, 655), 213, "E207-2", "控制工程研究室（二）"),
        numbered(s, (295, 218, 460, 655), 212, "E207-1", "控制工程研究室（一）"),
        numbered(s, (460, 218, 585, 415), 212, "E207-1", "材料室"),
        numbered(s, (460, 415, 585, 600), 211, "E206", "陶金旺教師研究室"),
        numbered(s, (1170, 218, 1300, 480), None, "E205-1", "材料室"),
        s.poly("room", [(1300, 218), (1650, 218), (1650, 580), (1550, 580), (1550, 650), (1170, 650),
                        (1170, 480), (1300, 480)], "電210", "微處理機／電腦模擬實驗室", "E205"),
        numbered(s, (1735, 218, 1915, 360), 209, "E204-3", "通訊研究室（四）"),
        numbered(s, (1735, 360, 1915, 495), 208, "E204-2", "通訊研究室（三）"),
        numbered(s, (1735, 495, 1915, 630), 207, "E204-1", "通訊研究室（二）"),
        numbered(s, (1625, 630, 1895, 745), None, "E203-1", "系主任辦公室"),
        numbered(s, (1615, 745, 1885, 1060), 205, "E203", "系辦公室"),
        numbered(s, (1290, 690, 1615, 1000), 206, "E204", "系會議室"),
        numbered(s, (1660, 1060, 1865, 1165), 202, "E202-1", "吳德豐教師研究室"),
        numbered(s, (1660, 1165, 1865, 1255), 203, "E202-2", "彭世興教師研究室"),
        numbered(s, (1600, 1255, 1865, 1360), 204, "E202-3", "江茂欽教師研究室"),
        numbered(s, (1290, 1110, 1600, 1360), 201, "E201", "通訊研究室（一）"),
        numbered(s, (160, 740, 470, 915), 214, "E208-5", "電力電子研究室（二）"),
        numbered(s, (165, 915, 320, 1045), 216, "E208-4", "智慧型電能轉換實驗室"),
        numbered(s, (320, 915, 470, 1045), 215, "E208-3", "智慧型控制轉換實驗室"),
        numbered(s, (175, 1045, 330, 1160), 218, "E208-2", "莊鎮嘉教師研究室"),
        numbered(s, (330, 1045, 475, 1160), 217, "E208-1", "王晃銘教師研究室"),
        numbered(s, (180, 1215, 335, 1330), 220, "E209-1", "教師研究室"),
        numbered(s, (335, 1215, 485, 1330), 219, "E209", "曾志成教師研究室"),
    ]
    # The walkway at the top of the south wing is 電資二館's bridge.
    bridge = {"to": "dianzi", "name": "電資二館", "at": list(s.pt(130, 698)), "toward": [0, 1]}
    return floor("2F", spaces, "電機工程學系", ["電機系", "電機"], [bridge])


def floor_3f():
    s = Sign([(70, 340), (1512, 385), (1515, 1225), (130, 1420)])
    spaces = [
        s.rect("corridor", (430, 690, 1515, 770)),
        s.rect("corridor", (440, 770, 520, 1420)),
        s.rect("corridor", (1355, 770, 1390, 1215)),
        s.rect("corridor", (1130, 480, 1170, 690)),
        s.rect("corridor", (1350, 480, 1385, 700)),
        *core(s, (720, 380, 960, 440), (660, 440, 935, 690), (770, 535, 845, 615),
              [((540, 355, 660, 560), "男廁"), ((550, 570, 665, 690), "女廁")]),
        s.rect("room", (75, 345, 265, 590), name="電資學院院長室"),
        s.poly("room", [(265, 350), (540, 355), (545, 735), (430, 735), (425, 590), (265, 590)],
               "電315", "電資學院辦公室"),
        numbered(s, (95, 590, 430, 830), 316, "E306", "電腦教室"),
        numbered(s, (105, 830, 440, 945), 317, "E305", "陳懷恩教師研究室"),
        numbered(s, (110, 945, 445, 1065), 318, "E304", "黃朝曦教師研究室"),
        numbered(s, (120, 1065, 450, 1185), 319, "E303", "黃于飛教師研究室"),
        numbered(s, (125, 1185, 455, 1300), 320, "E302", "朱志明教師研究室"),
        numbered(s, (130, 1300, 460, 1420), 321, "E301", "專任教師研究室"),
        s.poly("room", [(935, 375), (1125, 380), (1125, 485), (1010, 485), (1010, 585), (940, 585)],
               "電313", "網路展示室", "E308A"),
        numbered(s, (945, 590, 1010, 685), None, "E308B", "網路機房"),
        numbered(s, (1010, 485, 1130, 685), 312, "E308", "院會議兼討論室"),
        numbered(s, (1125, 380, 1350, 480), None, "E309", "專任老師實驗室"),
        numbered(s, (1170, 480, 1350, 580), 310, "E310B", "行動網路實驗室"),
        numbered(s, (1170, 580, 1350, 680), None, "E310A", "專任老師實驗室"),
        numbered(s, (1350, 385, 1512, 480), 309, "E314", "VoIP 實驗室"),
        numbered(s, (1385, 480, 1512, 575), 308, "E315", "RFID 實驗室"),
        numbered(s, (1385, 575, 1512, 700), 307, "E316", "圖學與視覺實驗室"),
        numbered(s, (1390, 770, 1515, 1030), 306, "E317", "資創中心展示室"),
        numbered(s, (1395, 1030, 1515, 1125), 305, "E318", "教師研究室"),
        numbered(s, (1365, 1125, 1515, 1225), 304, "E319", "夏至賢教師研究室"),
        numbered(s, (1135, 770, 1355, 1060), 303, "E311", "多媒體教室"),
        numbered(s, (1145, 1060, 1355, 1155), 302, "E312", "創客實驗室"),
        numbered(s, (1150, 1155, 1365, 1250), 301, "E313", "大數據實驗室"),
    ]
    return floor("3F", spaces, "電資學院", ["電資學院"])


def floor_4f():
    s = Sign([(20, 215), (1455, 280), (1420, 1225), (100, 1385)])
    spaces = [
        s.rect("corridor", (390, 640, 1180, 740)),
        s.rect("corridor", (395, 740, 500, 1250)),
        s.rect("corridor", (1100, 720, 1180, 1240)),
        s.rect("corridor", (1180, 390, 1220, 725)),
        s.rect("corridor", (280, 500, 395, 650)),
        *core(s, (700, 385, 945, 430), (710, 430, 945, 640), (760, 440, 860, 535),
              [((520, 240, 640, 460), "男廁"), ((560, 455, 660, 620), "無障礙廁所"),
               ((960, 265, 1075, 465), "女廁")]),
        s.poly("room", [(20, 220), (380, 232), (395, 500), (25, 500)], "電417", "資工系辦公室", "E407"),
        numbered(s, (380, 235, 520, 435), None, "E407A", "資工系系主任辦公室"),
        numbered(s, (385, 435, 525, 630), 416, "E408", "AI 與資料科學實驗室"),
        numbered(s, (25, 500, 280, 765), 418, "E407B", "資工系會議室"),
        numbered(s, (640, 250, 960, 385), 415, "E415", "多用途室（一）"),
        s.rect("room", (965, 465, 1045, 620), name="雕刻室"),
        numbered(s, (1075, 265, 1185, 500), 412, "E409", "研討室"),
        numbered(s, (1075, 500, 1180, 630), 413, "E407", "專題研究室（二）"),
        numbered(s, (1185, 270, 1450, 390), 411, "E408C", "智能影音信號處理實驗室"),
        numbered(s, (1220, 390, 1445, 505), 410, "E408B", "媒體通訊實驗室"),
        numbered(s, (1220, 505, 1445, 615), 409, "E408A2", "無線通訊實驗室"),
        numbered(s, (1220, 615, 1440, 725), 408, "E408A1", "嵌入式系統與行動計算實驗室"),
        numbered(s, (1180, 725, 1430, 835), 407, "E410A", "資通訊安全實驗室"),
        numbered(s, (1180, 835, 1425, 935), 406, "E410B", "智能訊號與資訊處理實驗室（iSIP）"),
        numbered(s, (1175, 935, 1420, 1035), 405, "E410C", "高效能運算實驗室"),
        # The user numbered E411's two halves 402 and 403.
        numbered(s, (1175, 1035, 1297, 1135), 402, "E411", "高速元件實驗室"),
        numbered(s, (1297, 1035, 1420, 1135), 403, "E411", "高速元件實驗室"),
        numbered(s, (1180, 1135, 1300, 1235), 401, "E413", "系學會辦公室"),
        numbered(s, (1300, 1135, 1420, 1225), None, "E412", "鄭岫盈教師研究室"),
        numbered(s, (45, 765, 425, 1045), 419, "E406", "電腦教室"),
        numbered(s, (85, 1045, 270, 1265), 422, "E403", "專題討論室"),
        numbered(s, (265, 1045, 435, 1125), 420, "E405", "教師研究室"),
        numbered(s, (270, 1125, 440, 1210), 421, "E402B", "夏至賢教師研究室"),
        numbered(s, (100, 1265, 280, 1385), 423, "E402", "教師研究室"),
        numbered(s, (280, 1245, 445, 1355), 425, "E401", "智慧型系統實驗室"),
    ]
    return floor("4F", spaces, "資訊工程學系", ["資工系", "資工"])


def floor_5f():
    s = Sign([(245, 175), (1765, 45), (1680, 1375), (300, 1215)])
    spaces = [
        s.rect("corridor", (520, 530, 1330, 660)),
        s.rect("corridor", (520, 660, 600, 1215)),
        s.rect("corridor", (1240, 525, 1325, 1300)),
        s.rect("corridor", (1320, 945, 1540, 1080)),
        *core(s, (735, 100, 1060, 260), (745, 260, 1055, 530), (840, 310, 945, 430),
              [((625, 140, 735, 350), "男廁"), ((660, 380, 745, 515), "男廁"),
               ((1060, 95, 1195, 365), "女廁"), ((1055, 370, 1150, 510), "女廁")]),
        numbered(s, (250, 165, 510, 295), None, "E505", "會議室"),
        numbered(s, (260, 295, 385, 400), None, "E505", "系主任辦公室"),
        s.poly("room", [(510, 150), (630, 145), (630, 530), (520, 530), (520, 400), (385, 400), (385, 295),
                        (510, 295)], "電516", "系辦公室", "E505"),
        s.poly("room", [(265, 400), (520, 400), (520, 535), (380, 535), (380, 640), (275, 640)],
               "E505", "儀器材料室"),
        numbered(s, (380, 535, 520, 640), 517, "E504", "會客室"),
        numbered(s, (275, 640, 535, 980), 518, "E503A", "電子電路實驗室"),
        numbered(s, (290, 980, 540, 1100), 519, "E503B", "光纖通訊元件設計量測實驗室"),
        numbered(s, (295, 1100, 415, 1210), 521, "E502", "教師研究室"),
        numbered(s, (415, 1105, 540, 1215), 520, "E501", "教師研究室"),
        numbered(s, (1195, 85, 1340, 370), 515, "E507", "高效能運算與網路設備"),
        numbered(s, (1190, 370, 1335, 525), 513, "E506A", "系圖書室"),
        numbered(s, (1340, 45, 1745, 525), 512, "E506B", "電腦輔助設計實驗室"),
        numbered(s, (1330, 525, 1730, 665), 511, "E508C", "積體電路設計實驗室"),
        numbered(s, (1325, 670, 1515, 805), 509, "E508A", "教師研究室"),
        numbered(s, (1515, 670, 1715, 815), 510, "E508B", "游竹教師研究室"),
        numbered(s, (1320, 805, 1505, 945), 508, "E509", "胡懷祖教師研究室"),
        numbered(s, (1505, 815, 1700, 955), 507, "E510", "林作俊教師研究室"),
        numbered(s, (1540, 960, 1695, 1100), 506, "E511", "兼任教師休息室"),
        numbered(s, (1535, 1100, 1685, 1230), 505, "E512", "教師研究室"),
        numbered(s, (1310, 1080, 1450, 1205), 501, "E515", "教師研究室"),
        numbered(s, (1305, 1205, 1485, 1330), 502, "E514", "教師研究室"),
        numbered(s, (1485, 1230, 1670, 1370), 503, "E513", "教師研究室"),
    ]
    return floor("5F", spaces, "電子工程學系", ["電子系", "電子"])


def floor_6f():
    s = Sign([(165, 200), (1830, 175), (1745, 1440), (225, 1360)])
    spaces = [
        s.rect("corridor", (520, 610, 1405, 745)),
        s.rect("corridor", (520, 745, 600, 1360)),
        s.rect("corridor", (1300, 745, 1405, 1310)),
        s.rect("corridor", (470, 340, 520, 745)),
        *core(s, (790, 195, 1130, 345), (785, 345, 1130, 610), (895, 395, 1000, 520),
              [((645, 195, 780, 425), "男廁"), ((1130, 185, 1275, 430), "女廁"),
               ((1130, 430, 1230, 605), "女廁")]),
        numbered(s, (180, 200, 510, 340), 611, "E604C", "智慧型資訊擷取實驗室"),
        numbered(s, (185, 340, 470, 475), 612, "E604B", "混合訊號積體電路設計實驗室"),
        numbered(s, (190, 475, 470, 740), 613, "E604A", "創客工作坊"),
        numbered(s, (205, 740, 520, 1120), 615, "E603A", "多功能展示室"),
        numbered(s, (215, 1120, 525, 1245), 616, "E603B", "高速網路實驗室"),
        numbered(s, (225, 1245, 375, 1360), 618, "E602", "郭芳璋教師研究室"),
        numbered(s, (375, 1245, 530, 1365), 617, "E601", "邱建文教師研究室"),
        numbered(s, (510, 195, 645, 400), 610, "E605", "專題研究室（三）"),
        numbered(s, (520, 400, 650, 610), 609, "E606", "物聯網實驗室"),
        s.rect("room", (685, 460, 785, 595), name="蝕刻室"),
        numbered(s, (1275, 185, 1420, 400), 608, "E609", "李棟村教師研究室"),
        numbered(s, (1270, 400, 1415, 610), None, "E607", "儲藏室"),
        numbered(s, (1420, 180, 1815, 765), 606, "E608", "智慧物聯網實驗室"),
        numbered(s, (1405, 765, 1775, 1180), 605, "E610", "通訊量測實驗室"),
        numbered(s, (1395, 1180, 1755, 1310), 603, "E611", "AI 系統實驗室"),
        numbered(s, (1390, 1310, 1560, 1440), 601, "E613", "教師研究室"),
        numbered(s, (1560, 1310, 1740, 1445), 602, "E612", "教師研究室"),
    ]
    return floor("6F", spaces)


def main():
    building = {
        "id": "gezhi",
        "name": "格致大樓（電資學院）",
        "unit": "m",
        "floors": [f() for f in (floor_1f, floor_2f, floor_3f, floor_4f, floor_5f, floor_6f)],
    }
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/gezhi.json", root / "mobile/assets/campus_map/gezhi.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
