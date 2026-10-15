#!/usr/bin/env python3
"""Generates app-content/campus-map/huodong.json (學生活動中心).

Sources, all photographed in the building:
- 1F: the emergency map beside the directory. It is drawn east up: north
  (the stage end with its slanted wall) on the left, the entrance lobby,
  lifts and toilets on the right.
- 2F: the architect's sign-layout plan (二層指標配置平面圖), north up: the
  outdoor terrace over the stage end, the hall's void with the balcony
  (二樓看台區) round it, and the south block with the 課外活動組 office.
- 3F–5F: the architect's plans (參層/肆層/伍層指標配置平面圖, north up)
  for the walls, and the floors' emergency maps (drawn west up) for the
  room numbers. The plans call the big east room 辦公室 or 多功能活動室;
  the emergency maps and the directory call it 研習室A, B and C, which is
  what the building uses now. Every numbered room is a 社團辦公室.

Fitting: the plans' scale bars don't match their drawings, so everything
is fitted to the OpenStreetMap outline instead. The 2F plan spans the whole
building, and its north end (the terrace block, the widest part) is matched
to the outline's north wall, its south end to the south wall; the upper
floors only cover the south block, measured off the 4F plan and placed by
the 2F plan. The building in OpenStreetMap leans a little east going south,
and `site` follows that lean. The plans show the office block standing
about 4 m proud of the hall's east wall, which OpenStreetMap leaves out.

The directory also lists B1 (排練室, 多功能活動室), but there is no plan of
it, so it isn't drawn. Rooms carry no codes: the building numbers its
club rooms plainly (305), so the number leads the name, as in the library.
"""
import json
from pathlib import Path


def site(p, q):
    """Plan metres (p east of the north block's west wall, q south of the
    north end) to the outline's metres."""
    return 3.5 + p + 0.037 * q, 0.4 + q - 0.011 * p


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
    """One photographed plan: four pixel points and where they are in plan
    metres, as a projective map. Pixels are in a crop of the photo; `at`
    turns crop pixels into the photo's 1600-px thumbnail."""

    def __init__(self, at, pairs):
        self.at = at
        a, b = [], []
        for (u, v), pq in pairs:
            u, v = at(u, v)
            x, y = site(*pq)
            a.append([u, v, 1, 0, 0, 0, -u * x, -v * x])
            b.append(x)
            a.append([0, 0, 0, u, v, 1, -u * y, -v * y])
            b.append(y)
        self.h = solve(a, b)

    def pt(self, u, v):
        u, v = self.at(u, v)
        h = self.h
        w = h[6] * u + h[7] * v + 1
        return [round((h[0] * u + h[1] * v + h[2]) / w, 2), round((h[3] * u + h[4] * v + h[5]) / w, 2)]

    def pts(self, ps):
        return [self.pt(*p) for p in ps]

    def poly(self, kind, ps, name=None, note=None):
        return labelled({"kind": kind, "polygon": self.pts(ps)}, name, note)

    def rect(self, kind, u0, v0, u1, v1, name=None, note=None):
        """A box on the sign: a rectangle in metres unless the fit skews it."""
        ps = self.pts([(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
        xs, ys = [p[0] for p in ps], [p[1] for p in ps]
        area = abs(sum(p[0] * q[1] - q[0] * p[1] for p, q in zip(ps, ps[1:] + ps[:1]))) / 2
        x0, y0 = min(xs), min(ys)
        if area > .97 * (max(xs) - x0) * (max(ys) - y0):
            space = {"kind": kind, "rect": [x0, y0, round(max(xs) - x0, 2), round(max(ys) - y0, 2)]}
        else:
            space = {"kind": kind, "polygon": ps}
        return labelled(space, name, note)

    def room(self, *box, name=None, note=None):
        return self.rect("room", *box, name=name, note=note)


def labelled(space, name, note):
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


def club(n):
    return f"{n} 社團辦公室"


# The south block, as the 4F plan draws it (crop pixels of IMG_6063, north
# up), in plan metres: 30 m from the west wall to 研習室B's east wall, and
# from the toilets' north wall to the south wall, as on the 2F plan.
def block(u, v):
    return 5.26 + (u - 18) / 42.6, 72.4 - (905 - v) / 38.2


def floor_1f():
    # IMG_6057, east up. Two zoomed crops of the map share one fit: the
    # stage end (`a`) and the lobby end (`b`).
    def a(x, y):
        return 50 + x / 3, 390 + y / 3

    def b(x, y):
        return a(x + 840, y)

    g = Sign(lambda u, v: (u, v), [(a(45, 1055), (0, 0)), (a(45, 45), (35, 0)),
                                   (b(850, 105), (35.2, 72.4)), (b(850, 860), (5.26, 72.4))])

    def slant(v):
        """The stage end's slanted north-east wall."""
        return 300 - (v - 45) * 255 / 695

    A = lambda ps: [a(*p) for p in ps]
    B = lambda ps: [b(*p) for p in ps]
    spaces = [
        g.poly("room", A([(280, 255), (1170, 255), (1170, 875), (280, 875)]), name="春男展演廳"),
        # The aisles down both sides of the hall, with stairs up to the
        # balcony at their north ends.
        g.rect("stairs", *a(540, 115), *a(640, 250)),
        g.rect("corridor", *a(640, 120), *b(235, 250)),
        g.rect("stairs", *a(550, 900), *a(655, 1040)),
        g.rect("corridor", *a(655, 880), *b(250, 1040)),
        # The stage end.
        g.room(*a(300, 130), *a(465, 265), name="貴賓休息室"),
        g.poly("room", A([(slant(410), 410), (230, 410), (230, 510), (slant(510), 510)]), name="準備室（三）"),
        g.poly("room", A([(slant(510), 510), (235, 510), (235, 625), (slant(625), 625)]), name="準備室（二）"),
        g.poly("room", A([(slant(625), 625), (235, 625), (235, 740), (slant(740), 740)]), name="準備室（一）"),
        g.room(*a(45, 740), *a(150, 795)),
        g.room(*a(45, 795), *a(240, 1040)),
        g.room(*a(390, 860), *a(550, 1025)),
        g.rect("stairs", *a(295, 960), *a(335, 1005)),
        # The lobby end.
        g.rect("restroom", *b(330, 260), *b(420, 390), name="女廁"),
        g.rect("restroom", *b(420, 260), *b(520, 390), name="男廁"),
        g.room(*b(330, 440), *b(430, 520), name="茶水間"),
        g.rect("restroom", *b(330, 520), *b(440, 580), name="無障礙廁所"),
        g.room(*b(515, 105), *b(740, 340)),
        g.rect("stairs", *b(635, 340), *b(740, 400)),
        g.rect("stairs", *b(665, 400), *b(740, 570)),
        g.rect("elevator", *b(600, 420), *b(650, 470)),
        g.rect("elevator", *b(600, 475), *b(650, 525)),
        g.rect("corridor", *b(520, 400), *b(600, 570)),
        g.room(*b(745, 465), *b(850, 575)),
        g.rect("corridor", *b(330, 580), *b(545, 880)),
        g.rect("stairs", *b(400, 820), *b(550, 860)),
        g.rect("corridor", *b(545, 580), *b(850, 860)),
    ]
    outline = g.pts(A([(300, 45), (635, 45), (635, 120)]) + B([(235, 120), (235, 250), (515, 250), (515, 105),
                                                                 (740, 105), (740, 465), (850, 465), (850, 860),
                                                                 (545, 860), (545, 880), (250, 880), (250, 1040)])
                    + A([(45, 1040), (45, 740)]))
    return {"id": "1F", "outline": outline, "spaces": spaces}


def floor_2f():
    # IMG_6059, north up; crop `a` is the north half, `b` the south.
    def a(x, y):
        return 130 + x / 1.6, 80 + y / 1.6

    def b(x, y):
        return a(x, y + 992)

    # The terrace block's west wall and its virtual north-east corner span
    # the outline's 35 m; the south block's south wall is its south end.
    g = Sign(lambda u, v: (u, v), [((227, 117), (0, 0)), ((892, 117), (35, 0)),
                                   ((896, 1265), (35.2, 72.4)), ((227, 1265), (0, 72.4))])
    A = lambda ps: [a(*p) for p in ps]
    B = lambda ps: [b(*p) for p in ps]
    spaces = [
        g.poly("terrace", A([(155, 60), (500, 60), (1215, 325), (1215, 615), (1060, 615), (1060, 340),
                             (290, 340), (290, 615), (155, 615)]), name="戶外平台"),
        g.room(*a(315, 350), *a(500, 615), name="空調機房"),
        g.rect("void", *a(500, 350), *a(865, 615)),
        g.room(*a(865, 350), *a(1055, 615), name="空調機房"),
        # The balcony round the hall: aisles down the sides, seats across
        # the south end.
        g.rect("corridor", *a(312, 620), *b(375, 230)),
        g.rect("corridor", *a(995, 620), *b(1060, 230)),
        g.room(*b(312, 230), *b(1060, 330), name="二樓看台區"),
        g.rect("void", *a(375, 620), *b(995, 230)),
        g.room(*b(322, 240), *b(400, 300), name="機械室"),
        g.room(*b(980, 240), *b(1052, 300), name="機械室"),
        # The south block.
        g.rect("stairs", *b(322, 335), *b(410, 540)),
        g.poly("corridor", B([(410, 335), (580, 335), (580, 440), (860, 440), (860, 545), (410, 545)])),
        g.room(*b(580, 335), *b(780, 440), name="機械室"),
        g.room(*b(785, 335), *b(860, 440), name="儲藏室"),
        g.rect("restroom", *b(880, 335), *b(1045, 445), name="女廁"),
        g.rect("restroom", *b(880, 455), *b(1045, 545), name="男廁"),
        g.rect("corridor", *b(860, 335), *b(880, 545)),
        g.rect("void", *b(330, 560), *b(675, 905)),
        g.poly("corridor", B([(675, 545), (860, 545), (860, 620), (730, 620), (730, 760), (675, 760)])),
        g.rect("elevator", *b(735, 625), *b(785, 698)),
        g.rect("elevator", *b(790, 625), *b(850, 698)),
        g.rect("stairs", *b(700, 700), *b(860, 795)),
        g.rect("void", *b(680, 800), *b(800, 915)),
        g.rect("stairs", *b(878, 675), *b(945, 795)),
        g.poly("room", B([(862, 548), (1225, 548), (1225, 800), (945, 800), (945, 672), (862, 672)]),
               name="辦公室", note="課外活動組"),
    ]
    outline = g.pts(A([(155, 60), (500, 60), (1215, 325), (1215, 615), (1060, 615)])
                    + B([(1060, 330), (1045, 330), (1045, 545), (1225, 545), (1225, 800), (800, 800), (800, 915),
                         (315, 915), (312, 330)]) + A([(312, 615), (155, 615)]))
    return {"id": "2F", "outline": outline, "spaces": spaces, "unit": "課外活動組"}


def floor_3f():
    # IMG_6066, the 3F plan photographed turned: west up, north on the
    # right. Fitted to the 4F plan by the south-west corner, 乙梯's
    # north-west corner, 研習室A's south-east corner and the toilets'
    # north-east corner.
    g = Sign(lambda x, y: (x + 270, y + 200), [((20, 25), block(18, 905)), ((560, 20), block(15, 225)),
                                                ((160, 1060), block(1295, 690)), ((690, 860), block(1060, 40))])
    spaces = [
        *[g.room(u0, 25, u1, 150, name=club(n))
          for n, u0, u1 in ((305, 20, 105), (306, 105, 195), (307, 195, 285), (308, 285, 370), (309, 370, 455))],
        g.rect("stairs", 455, 20, 560, 205),
        g.rect("terrace", 0, 150, 20, 205),
        g.room(20, 210, 190, 300, name=club(304)),
        g.room(20, 300, 190, 390, name=club(303)),
        g.room(30, 390, 190, 585, name=club(302)),
        g.room(280, 205, 445, 300, name=club(310)),
        g.room(280, 300, 445, 390, name=club(311)),
        g.rect("corridor", 20, 150, 455, 205),
        g.rect("corridor", 190, 205, 280, 455),
        g.rect("corridor", 280, 390, 445, 455),
        g.poly("terrace", [(560, 20), (690, 20), (690, 450), (450, 450), (450, 205), (560, 205)],
               name="戶外觀景休憩區"),
        g.rect("stairs", 165, 455, 270, 650),
        g.rect("elevator", 270, 495, 360, 572),
        g.rect("elevator", 270, 575, 360, 640),
        g.poly("corridor", [(270, 455), (445, 455), (445, 650), (360, 650), (360, 495), (270, 495)]),
        g.room(450, 450, 690, 650, name="活動交誼空間"),
        g.room(165, 655, 345, 755, name=club(301)),
        g.rect("corridor", 345, 650, 445, 760),
        g.room(160, 760, 425, 1060, name="研習室A"),
        g.room(450, 655, 560, 745, name="茶水間"),
        g.rect("restroom", 445, 745, 560, 860, name="男廁"),
        g.rect("restroom", 560, 650, 690, 860, name="女廁"),
    ]
    outline = g.pts([(20, 25), (560, 20), (690, 20), (690, 860), (425, 860), (425, 1060), (160, 1060), (160, 650),
                     (30, 650), (30, 585), (20, 585)])
    return {"id": "3F", "outline": outline, "spaces": spaces}


def floor_4f():
    # IMG_6063, north up: the reference for the south block.
    g = Sign(lambda u, v: (290 + u / 1.2, 240 + v / 1.2),
             [((u, v), block(u, v)) for u, v in ((18, 905), (1295, 905), (1295, 20), (18, 20))])
    spaces = [
        g.rect("stairs", 15, 225, 255, 365),
        *[g.room(18, v0, 190, v1, name=club(n))
          for n, v0, v1 in ((409, 365, 495), (408, 495, 585), (407, 585, 690), (406, 690, 800), (405, 800, 905))],
        g.rect("corridor", 190, 365, 265, 905),
        g.room(262, 360, 365, 578, name=club(410)),
        g.room(365, 360, 462, 578, name=club(411)),
        g.poly("corridor", [(265, 578), (462, 578), (462, 360), (565, 360), (565, 700), (265, 700)]),
        g.room(265, 700, 375, 905, name=club(404)),
        g.room(375, 700, 490, 905, name=club(403)),
        g.room(490, 700, 740, 905, name=club(402)),
        g.room(545, 20, 830, 360, name="活動交誼空間"),
        g.rect("restroom", 830, 20, 1060, 200, name="女廁"),
        g.room(830, 200, 905, 360, name="茶水間"),
        g.rect("restroom", 905, 200, 1060, 345, name="男廁"),
        g.poly("corridor", [(565, 360), (940, 360), (940, 460), (830, 460), (830, 470), (565, 470)]),
        g.rect("elevator", 625, 470, 695, 570),
        g.rect("elevator", 710, 470, 790, 570),
        g.rect("stairs", 565, 575, 805, 695),
        g.room(835, 460, 940, 690, name=club(401)),
        g.room(940, 345, 1295, 690, name="研習室B"),
    ]
    outline = g.pts([(15, 225), (255, 225), (255, 360), (545, 360), (545, 20), (1060, 20), (1060, 345), (1295, 345),
                     (1295, 690), (740, 695), (740, 905), (18, 905)])
    return {"id": "4F", "outline": outline, "spaces": spaces}


def floor_5f():
    # IMG_6064, north up, fitted to the 4F plan like 3F.
    g = Sign(lambda x, y: (205 + x / 1.05, 100 + y / 1.05),
             [((30, 860), block(18, 905)), ((12, 222), block(15, 225)), ((1280, 690), block(1295, 690)),
              ((1035, 15), block(1060, 25))])
    spaces = [
        g.rect("stairs", 12, 222, 225, 350),
        *[g.room(30, v0, 165, v1, name=club(n))
          for n, v0, v1 in ((509, 355, 460), (508, 460, 560), (507, 560, 660), (506, 660, 760), (505, 760, 860))],
        g.rect("corridor", 165, 350, 240, 860),
        g.room(235, 350, 335, 555, name=club(510)),
        g.room(335, 350, 430, 555, name=club(511)),
        g.poly("corridor", [(240, 555), (430, 555), (430, 350), (525, 350), (525, 670), (240, 670)]),
        g.room(240, 670, 345, 855, name=club(504)),
        g.room(345, 670, 450, 855, name=club(503)),
        g.room(450, 680, 545, 850, name=club(502)),
        g.rect("terrace", 545, 690, 690, 845, name="平台"),
        g.rect("terrace", 180, 860, 240, 900),
        *[g.room(u0, 15, u1, 240, name=club(n)) for n, u0, u1 in ((512, 505, 605), (513, 605, 700), (514, 700, 795))],
        g.rect("corridor", 505, 240, 795, 345),
        g.rect("restroom", 795, 15, 880, 160, name="無障礙廁所"),
        g.rect("restroom", 880, 15, 1035, 190, name="女廁"),
        g.room(795, 190, 890, 340, name="茶水間"),
        g.rect("restroom", 890, 190, 1035, 340, name="男廁"),
        g.poly("corridor", [(525, 345), (900, 345), (900, 455), (795, 455), (795, 460), (525, 460)]),
        g.rect("elevator", 590, 460, 660, 545),
        g.rect("elevator", 670, 460, 745, 545),
        g.rect("stairs", 545, 555, 790, 680),
        g.room(795, 455, 900, 690, name=club(501)),
        g.room(900, 335, 1280, 690, name="研習室C"),
    ]
    outline = g.pts([(12, 222), (225, 222), (225, 350), (505, 350), (505, 15), (1035, 15), (1035, 335), (1280, 335),
                     (1280, 690), (690, 690), (690, 850), (240, 858), (240, 900), (180, 900), (180, 860), (30, 860),
                     (30, 355), (12, 355)])
    return {"id": "5F", "outline": outline, "spaces": spaces}


def main():
    floors = [f() for f in (floor_1f, floor_2f, floor_3f, floor_4f, floor_5f)]
    building = {"id": "huodong", "name": "學生活動中心", "unit": "m", "floors": floors}
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/huodong.json", root / "mobile/assets/campus_map/huodong.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
