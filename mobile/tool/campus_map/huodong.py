#!/usr/bin/env python3
"""Generates app-content/campus-map/huodong.json (學生活動中心).

Sources, all photographed in the building:
- 1F: the emergency map in the lobby (IMG_6058; IMG_6057 is the same map
  beside the directory). It is drawn east up: north (the stage end with its
  slanted wall) on the left, the entrance lobby, lifts and toilets on the
  right.
- 2F: the architect's sign-layout plan (二層指標配置平面圖), north up: the
  outdoor terrace over the stage end, the hall's void with the balcony
  (二樓看台區) round it, and the south block with the 課外活動組 office.
- 3F–5F: the architect's plans (參層/肆層/伍層指標配置平面圖, north up;
  the 3F one photographed turned, west up) for the walls, and the floors'
  emergency maps (drawn west up) for the room numbers. The plans call the
  big east room 辦公室 or 多功能活動室; the emergency maps and the
  directory call it 研習室A, B and C, which is what the building uses now.
  Every numbered room is a 社團辦公室.

Drawn square to the compass, walls straight: each photo is mapped axis by
axis, piecewise linearly between wall lines it shares with the other
floors, so rooms that share a wall share its coordinate and the floors
stack. The plans' scale bars don't match their drawings, so the lengths
come from the OpenStreetMap outline instead (35 m across the stage end,
72.4 m from the north tip to the south wall), the hall made about square
(24.5 × 26 m) as it is. The only slanted wall is the stage end's real
north-east façade. The plans show the office block standing a little
proud of the hall's east wall, which OpenStreetMap leaves out.

The directory also lists B1 (排練室, 多功能活動室), but there is no plan of
it, so it isn't drawn. Rooms carry no codes: the building numbers its
club rooms plainly (305), so the number leads the name, as in the library.
"""
import json
from pathlib import Path

WEST = 3.5  # the outline's x of the stage end's west wall


class Axis:
    """Pixels to metres along one axis, linear between knots."""

    def __init__(self, *knots):
        self.k = sorted(knots)

    def __call__(self, p):
        k = self.k
        i = 1
        while i < len(k) - 1 and p > k[i][0]:
            i += 1
        (p0, m0), (p1, m1) = k[i - 1], k[i]
        return m0 + (p - p0) * (m1 - m0) / (p1 - p0)


class Plan:
    """One photographed plan. `east` and `south` are Axes in metres (east of
    the stage end's west wall, south of the north tip); `turned` says the
    picture's x runs north–south."""

    def __init__(self, east, south, turned=False):
        self.east, self.south, self.turned = east, south, turned

    def pt(self, u, v):
        if self.turned:
            u, v = v, u
        return [round(WEST + self.east(u), 2), round(self.south(v), 2)]

    def pts(self, ps):
        return [self.pt(*p) for p in ps]

    def poly(self, kind, ps, name=None, note=None):
        return labelled({"kind": kind, "polygon": self.pts(ps)}, name, note)

    def rect(self, kind, u0, v0, u1, v1, name=None, note=None):
        (xa, ya), (xb, yb) = self.pt(u0, v0), self.pt(u1, v1)
        x0, y0 = min(xa, xb), min(ya, yb)
        space = {"kind": kind, "rect": [x0, y0, round(abs(xb - xa), 2), round(abs(yb - ya), 2)]}
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


# The south block, which every upper floor shares, by the 4F plan's crop
# pixels (IMG_6063): 30 m from the west wall to 研習室B's east wall, and
# from the hall's south wall to the building's.
EAST4 = Axis((18, 5.2), (1295, 35.2))
SOUTH4 = Axis((20, 48.0), (905, 72.4))


def floor_1f():
    # IMG_6058 (1600-px thumbnail), east up: x runs north to south, y east
    # to west.
    g = Plan(Axis((195, 35.5), (233, 35.2), (240, 34.6), (327, 29.7), (727, 5.2), (808, 1.5), (850, 0)),
             Axis((312, 0), (472, 10.5), (608, 22), (985, 48), (1310, 72.4)), turned=True)

    def slant(v):
        """The stage end's slanted north-east wall, x at y."""
        return 472 - (v - 195) * 160 / 425

    spaces = [
        g.room(608, 327, 985, 727, name="春男展演廳"),
        # Aisles down both sides of the hall, with stairs up to the balcony.
        g.rect("stairs", 608, 240, 670, 327),
        g.rect("corridor", 670, 240, 930, 327),
        g.rect("stairs", 608, 727, 670, 850),
        g.rect("corridor", 670, 727, 930, 850),
        # The stage end.
        g.poly("corridor", [(slant(195), 195), (608, 195), (608, 245), (slant(245), 245)]),
        g.poly("room", [(slant(245), 245), (570, 245), (570, 330), (slant(330), 330)], name="貴賓休息室"),
        g.room(570, 245, 608, 330),
        g.poly("corridor", [(slant(330), 330), (608, 330), (608, 420), (slant(420), 420)]),
        g.room(515, 330, 545, 380),
        g.rect("stairs", 565, 350, 595, 390),
        g.poly("room", [(slant(420), 420), (425, 420), (425, 480), (slant(480), 480)], name="準備室（三）"),
        g.poly("room", [(slant(480), 480), (425, 480), (425, 555), (slant(555), 555)], name="準備室（二）"),
        g.poly("room", [(slant(555), 555), (425, 555), (425, 620), (312, 620)], name="準備室（一）"),
        g.room(312, 620, 425, 652),
        g.room(312, 652, 425, 808),
        g.room(462, 420, 608, 625),
        g.poly("corridor", [(425, 420), (462, 420), (462, 625), (608, 625), (608, 700), (512, 700), (512, 808),
                            (425, 808)]),
        g.rect("stairs", 565, 678, 595, 700),
        g.room(512, 700, 608, 808),
        # The lobby end.
        g.rect("restroom", 985, 327, 1045, 430, name="女廁"),
        g.rect("restroom", 1045, 327, 1105, 430, name="男廁"),
        g.poly("corridor", [(985, 430), (1105, 430), (1105, 535), (1045, 535), (1045, 440), (985, 440)]),
        g.room(985, 440, 1045, 495, name="茶水間"),
        g.rect("restroom", 985, 495, 1045, 535, name="無障礙廁所"),
        g.room(1105, 233, 1245, 380),
        g.rect("stairs", 1175, 380, 1245, 425),
        g.poly("corridor", [(1105, 380), (1175, 380), (1175, 425), (1195, 425), (1195, 535), (1105, 535)]),
        g.rect("elevator", 1150, 435, 1190, 467),
        g.rect("elevator", 1150, 467, 1190, 500),
        g.rect("stairs", 1195, 425, 1245, 535),
        g.room(1245, 465, 1310, 535),
        g.rect("corridor", 985, 535, 1310, 727),
        g.rect("stairs", 1020, 690, 1115, 727),
    ]
    outline = g.pts([(472, 195), (608, 195), (608, 240), (930, 240), (930, 327), (1105, 327), (1105, 233),
                     (1245, 233), (1245, 465), (1310, 465), (1310, 727), (930, 727), (930, 850), (608, 850),
                     (608, 808), (312, 808), (312, 620)])
    return {"id": "1F", "outline": outline, "spaces": spaces}


def floor_2f():
    # IMG_6059, north up; `a` is a zoomed crop of the north half, `b` of
    # the south, both turned back into the 1600-px thumbnail.
    east = Axis((227, 0), (325, 5.2), (792.5, 29.7), (889, 35.0), (895.6, 35.2))
    south = Axis((117, 0), (283, 10.5), (464.4, 22), (906.25, 48), (1265, 72.4))

    class Two(Plan):
        def pt(self, x, y):
            return super().pt(130 + x / 1.6, 80 + y / 1.6)

    g = Two(east, south)
    B = 992  # crop b's y is crop a's less this
    spaces = [
        g.poly("terrace", [(155, 60), (500, 60), (1215, 325), (1215, 615), (1060, 615), (1060, 340), (312, 340),
                           (312, 615), (155, 615)], name="戶外平台"),
        g.room(312, 340, 500, 615, name="空調機房"),
        g.rect("void", 500, 340, 865, 615),
        g.room(865, 340, 1060, 615, name="空調機房"),
        # The balcony round the hall's void, down both sides to the
        # seats across its south end.
        g.poly("room", [(312, 615), (375, 615), (375, 230 + B), (995, 230 + B), (995, 615), (1060, 615),
                        (1060, 330 + B), (312, 330 + B)], name="二樓看台區"),
        g.rect("void", 375, 615, 995, 230 + B),
        g.room(320, 240 + B, 400, 300 + B, name="機械室"),
        g.room(980, 240 + B, 1052, 300 + B, name="機械室"),
        # The south block.
        g.rect("stairs", 312, 330 + B, 410, 545 + B),
        g.poly("corridor", [(410, 330 + B), (580, 330 + B), (580, 440 + B), (860, 440 + B), (860, 330 + B),
                            (880, 330 + B), (880, 545 + B), (410, 545 + B)]),
        g.room(580, 330 + B, 785, 440 + B, name="機械室"),
        g.room(785, 330 + B, 860, 440 + B, name="儲藏室"),
        g.rect("restroom", 880, 330 + B, 1060, 450 + B, name="女廁"),
        g.rect("restroom", 880, 450 + B, 1060, 545 + B, name="男廁"),
        g.rect("void", 312, 545 + B, 675, 915 + B),
        g.poly("corridor", [(675, 545 + B), (860, 545 + B), (860, 620 + B), (730, 620 + B), (730, 700 + B),
                            (675, 700 + B)]),
        g.rect("elevator", 730, 620 + B, 790, 700 + B),
        g.rect("elevator", 790, 620 + B, 860, 700 + B),
        g.rect("stairs", 675, 700 + B, 860, 800 + B),
        g.rect("void", 675, 800 + B, 800, 915 + B),
        g.rect("stairs", 860, 675 + B, 945, 800 + B),
        g.poly("room", [(860, 545 + B), (1225, 545 + B), (1225, 800 + B), (945, 800 + B), (945, 675 + B),
                        (860, 675 + B)], name="辦公室", note="課外活動組"),
    ]
    outline = g.pts([(155, 60), (500, 60), (1215, 325), (1215, 615), (1060, 615), (1060, 545 + B),
                     (1225, 545 + B), (1225, 800 + B), (800, 800 + B), (800, 915 + B), (312, 915 + B),
                     (312, 615), (155, 615)])
    return {"id": "2F", "outline": outline, "spaces": spaces, "unit": "課外活動組"}


def floor_3f():
    # IMG_6066, the 3F plan photographed turned: west up, north on the
    # right (crop pixels, x running south to north, y west to east). Its
    # wall lines are matched to the 4F plan's.
    g = Plan(Axis((22, EAST4(18)), (455, EAST4(545)), (760, EAST4(940)), (1060, EAST4(1295))),
             Axis((20, SOUTH4(905)), (160, SOUTH4(692)), (440, SOUTH4(362)), (560, SOUTH4(225)),
                  (690, SOUTH4(20))), turned=True)
    spaces = [
        *[g.room(x0, 22, x1, 150, name=club(n))
          for n, x0, x1 in ((305, 20, 105), (306, 105, 195), (307, 195, 285), (308, 285, 370), (309, 370, 455))],
        g.rect("stairs", 455, 22, 560, 205),
        g.rect("terrace", 0, 150, 20, 205),
        g.rect("corridor", 20, 150, 455, 205),
        g.room(20, 205, 190, 300, name=club(304)),
        g.room(20, 300, 190, 390, name=club(303)),
        g.room(20, 390, 160, 585, name=club(302)),
        g.room(280, 205, 440, 300, name=club(310)),
        g.room(280, 300, 440, 390, name=club(311)),
        g.rect("corridor", 190, 205, 280, 390),
        g.rect("corridor", 160, 390, 440, 455),
        g.poly("terrace", [(560, 22), (690, 22), (690, 455), (440, 455), (440, 205), (560, 205)],
               name="戶外觀景休憩區"),
        g.rect("stairs", 160, 455, 270, 655),
        g.rect("corridor", 270, 455, 440, 655),
        g.rect("elevator", 270, 495, 360, 575),
        g.rect("elevator", 270, 575, 360, 655),
        g.room(440, 455, 690, 655, name="活動交誼空間"),
        g.room(160, 655, 345, 760, name=club(301)),
        g.rect("corridor", 345, 655, 440, 760),
        g.room(160, 760, 440, 1060, name="研習室A"),
        g.room(440, 655, 560, 745, name="茶水間"),
        g.rect("restroom", 440, 745, 560, 860, name="男廁"),
        g.rect("restroom", 560, 655, 690, 860, name="女廁"),
    ]
    outline = g.pts([(20, 22), (690, 22), (690, 860), (440, 860), (440, 1060), (160, 1060), (160, 585), (20, 585),
                     (20, 205), (0, 205), (0, 150), (20, 150)])
    return {"id": "3F", "outline": outline, "spaces": spaces}


def floor_4f():
    # IMG_6063, north up (crop pixels): the reference for the south block.
    g = Plan(EAST4, SOUTH4)
    spaces = [
        g.rect("stairs", 18, 225, 265, 362),
        *[g.room(18, y0, 190, y1, name=club(n))
          for n, y0, y1 in ((409, 362, 495), (408, 495, 585), (407, 585, 690), (406, 690, 800), (405, 800, 905))],
        g.rect("corridor", 190, 362, 265, 905),
        g.rect("terrace", 190, 905, 265, 925),
        g.room(265, 362, 365, 578, name=club(410)),
        g.room(365, 362, 462, 578, name=club(411)),
        g.poly("corridor", [(265, 578), (462, 578), (462, 362), (940, 362), (940, 460), (830, 460), (830, 572),
                            (565, 572), (565, 692), (265, 692)]),
        g.rect("elevator", 625, 470, 695, 572),
        g.rect("elevator", 710, 470, 790, 572),
        g.room(790, 470, 830, 572),
        g.rect("stairs", 565, 572, 830, 692),
        g.room(265, 692, 375, 905, name=club(404)),
        g.room(375, 692, 490, 905, name=club(403)),
        g.room(490, 692, 740, 905, name=club(402)),
        g.room(545, 20, 830, 362, name="活動交誼空間"),
        g.rect("restroom", 830, 20, 1060, 200, name="女廁"),
        g.room(830, 200, 905, 362, name="茶水間"),
        g.rect("restroom", 905, 200, 1060, 362, name="男廁"),
        g.room(830, 460, 940, 692, name=club(401)),
        g.room(940, 362, 1295, 692, name="研習室B"),
    ]
    outline = g.pts([(18, 225), (265, 225), (265, 362), (545, 362), (545, 20), (1060, 20), (1060, 362), (1295, 362),
                     (1295, 692), (740, 692), (740, 905), (265, 905), (265, 925), (190, 925), (190, 905), (18, 905)])
    return {"id": "4F", "outline": outline, "spaces": spaces}


def floor_5f():
    # IMG_6064, north up (crop pixels), its wall lines matched to 4F's.
    g = Plan(Axis((30, EAST4(18)), (505, EAST4(545)), (900, EAST4(940)), (1280, EAST4(1295))),
             Axis((15, SOUTH4(20)), (222, SOUTH4(225)), (345, SOUTH4(362)), (680, SOUTH4(692)),
                  (860, SOUTH4(905))))
    spaces = [
        g.rect("stairs", 30, 222, 240, 345),
        *[g.room(30, y0, 165, y1, name=club(n))
          for n, y0, y1 in ((509, 345, 460), (508, 460, 560), (507, 560, 660), (506, 660, 760), (505, 760, 860))],
        g.rect("corridor", 165, 345, 240, 860),
        g.rect("terrace", 180, 860, 240, 900),
        g.room(240, 345, 335, 555, name=club(510)),
        g.room(335, 345, 430, 555, name=club(511)),
        g.poly("corridor", [(240, 555), (430, 555), (430, 345), (505, 345), (505, 240), (795, 240), (795, 345),
                            (900, 345), (900, 455), (795, 455), (795, 555), (545, 555), (545, 670), (240, 670)]),
        g.rect("elevator", 590, 455, 660, 545),
        g.rect("elevator", 670, 455, 745, 545),
        g.room(745, 455, 795, 545),
        g.rect("stairs", 545, 555, 795, 680),
        g.room(240, 670, 345, 860, name=club(504)),
        g.room(345, 670, 450, 860, name=club(503)),
        g.room(450, 670, 545, 860, name=club(502)),
        g.rect("terrace", 545, 680, 690, 860, name="平台"),
        *[g.room(x0, 15, x1, 240, name=club(n)) for n, x0, x1 in ((512, 505, 605), (513, 605, 700), (514, 700, 795))],
        g.rect("restroom", 795, 15, 885, 160, name="無障礙廁所"),
        g.rect("restroom", 885, 15, 1035, 190, name="女廁"),
        g.room(795, 160, 885, 345, name="茶水間"),
        g.rect("restroom", 885, 190, 1035, 345, name="男廁"),
        g.room(795, 455, 900, 680, name=club(501)),
        g.room(900, 345, 1280, 680, name="研習室C"),
    ]
    outline = g.pts([(30, 222), (240, 222), (240, 345), (505, 345), (505, 15), (1035, 15), (1035, 345), (1280, 345),
                     (1280, 680), (690, 680), (690, 860), (240, 860), (240, 900), (180, 900), (180, 860), (30, 860)])
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
