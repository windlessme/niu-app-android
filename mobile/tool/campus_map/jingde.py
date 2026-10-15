#!/usr/bin/env python3
"""Generates app-content/campus-map/jingde.json (經德大樓).

Read off the evacuation map on each floor and drawn on one axis-aligned
metre grid, north up. The building is a ring of rooms round an open
courtyard: a north block 40 m wide (x 6–46, a 2.5 m step out to 48.5 from
y 12), and a south wing 54.8 m wide reaching 6 m further west (from y 29)
and further east (from y 34.3). The outline's size comes from
OpenStreetMap; its slight tilt there is dropped.

The signs hang different ways round. 1F, 3F and 4F are north up; 5F and 6F
are drawn upside down (south up, the toilets on the left); 7F has west up
and north on the right. Each floor's corner toilets, lifts and stairs
confirm the turn. The signs are not to scale, so each is read through its
own piecewise-linear scale whose knots are the walls every floor shares
(courtyard, corridors, outer steps); the stairs, lifts, corner toilets and
the courtyard are then drawn once (`SHELL`) and line up floor to floor.

2F has no evacuation map, only a directory poster that is not to scale;
its rooms go in 3F's walls, in the poster's order and proportions. The
poster gives the rooms' codes, 經 plus a number (經201), so they go in
`code`. 6F and 7F are 國立空中大學's 宜蘭學習指導中心; its own boards
name some classrooms 6B–6D and 7A–7C, kept in `aka`.

1F has no rooms west of the north block's line: the south wing's west end
there is the outside ramp and stair. The room by the north-west stair is
labelled by hand on tape (書店, 咖啡・文創). 3F's map still prints older
names; the board beside it lists 生物機電工程學系's rooms 301–312 without
saying where they are, so the floor carries the department but the rooms
keep the map's names.
"""
import json
from pathlib import Path

# Wall lines, metres. x east, y south.
W0, W1, WC, CW, CE, EC, E1, E2, E3 = 0, 6, 13.2, 15.9, 33.4, 36.2, 46, 48.5, 54.8
N0, NR, NC, NBOX, WSTEP, CORE, ESTEP, CS, SR, S = 0, 8.5, 12, 15.6, 29, 31.8, 34.3, 35.1, 38.9, 50
# x: south wing west, north block west, west rooms' east wall, courtyard,
#    east rooms' west wall, north block east, east wall, south wing east.
# y: north wall, north rooms' south wall, courtyard north (and the east
#    step), east box, west step, lift line, east step, courtyard south,
#    south rooms' north wall, south wall.
TOILET_N = 38.2  # north-east toilets start here
TOILET_S = 44.7  # south-east toilets start here
TOILET_S_SPLIT = 50.0

OUTLINE = [[W1, N0], [E1, N0], [E1, NC], [E2, NC], [E2, ESTEP], [E3, ESTEP], [E3, S], [W0, S], [W0, WSTEP],
           [W1, WSTEP]]
SPACE = "國立空中大學宜蘭學習指導中心"


def scale(*knots):
    """Piecewise-linear map from sign pixels to metres through (pixel, metre)
    knots, extended past the ends."""
    ks = sorted(knots)

    def f(p):
        for (p0, m0), (p1, m1) in zip(ks, ks[1:]):
            if p <= p1 or (p1, m1) == ks[-1]:
                if p >= p0 or (p0, m0) == ks[0]:
                    return round(m0 + (p - p0) * (m1 - m0) / (p1 - p0), 1)
        raise ValueError(p)

    return f


def rect(kind, x0, y0, x1, y1, name=None, note=None, code=None, aka=None):
    x0, x1 = sorted((x0, x1))
    y0, y1 = sorted((y0, y1))
    space = {"kind": kind, "rect": [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)]}
    if code:
        space["code"] = f"經{code}"
    if aka:
        space["aka"] = aka
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


def room(*box, **label):
    return rect("room", *box, **label)


def row(y0, y1, edges, labels):
    """Rooms side by side between x edges, west to east; a label of None
    leaves that stretch as corridor."""
    assert len(edges) == len(labels) + 1, (edges, labels)
    return [room(a, y0, b, y1, **label) for a, b, label in zip(edges, edges[1:], labels) if label is not None]


def L(name=None, **extra):
    return {"name": name, **extra}


# Every floor's stairs, lifts and corner toilets, and the two small rooms
# beside the east rooms.
NW_STAIRS = rect("stairs", 11.6, 3.4, 14.6, NR)
NE_STAIRS = rect("stairs", 43.0, NR, E1, NC)
W_STAIRS = rect("stairs", W1, WSTEP, 11.9, CORE)
LIFT = rect("elevator", 9.3, CORE, 12.2, CS)
SE_STAIRS = rect("stairs", 51.0, ESTEP, E3, SR)
N_TOILETS = [rect("restroom", TOILET_N, N0, 42.0, 7.4, name="女廁"), rect("restroom", 42.0, N0, E1, NR, name="男廁")]
S_TOILETS = [rect("restroom", TOILET_S, 40.2, TOILET_S_SPLIT, S, name="女廁"),
             rect("restroom", TOILET_S_SPLIT, 40.2, E3, S, name="男廁")]
BOXES = [room(40.8, NC, E2, NBOX), room(41.9, CORE, E2, CS)]
SHELL = [NW_STAIRS, NE_STAIRS, W_STAIRS, LIFT, SE_STAIRS, *N_TOILETS, *S_TOILETS]
COURTYARD = rect("void", CW, NC, CE, CS)


def floor_1f():
    # North up. The south wing stops at the north block's west wall; the
    # ramp and stair outside it are open air. No small rooms on the east.
    fx = scale((640, W1), (782, CW), (1050, CE), (1090, EC), (1230, E1), (1247, E2), (1335, E3))
    fy = scale((292, N0), (405, NR), (440, NC), (805, CS), (840, SR), (970, S))
    north = [W1, 14.6, fx(857), fx(1004), TOILET_N]
    south = [W1, CW, fx(840), fx(897), EC, TOILET_S]
    spaces = [
        *SHELL,
        *row(N0, NR, north, [None, L("書店", note="咖啡・文創"), L("研究室（一）（二）"), L("研究室（三）")]),
        rect("stairs", fx(600), fy(410), W1, fy(490)),
        rect("terrace", CW, NC, CE, CS, name="中庭平台"),
        rect("stairs", CW, fy(500), fx(880), fy(550)),
        rect("stairs", CW, fy(730), fx(888), fy(762)),
        room(EC, NBOX, E2, CORE, name="電腦教室"),
        room(south[0], SR, south[1], S, name="文書組辦公室"),
        room(south[1], fy(870), south[2], S, name="檔案室"),
        room(south[2], fy(870), south[3], S, name="檔案室"),
        room(south[3], SR, south[4], S, name="進修部辦公室"),
        room(south[4], SR, south[5], S, name="進修部"),
    ]
    outline = [[W1, N0], [E1, N0], [E1, NC], [E2, NC], [E2, ESTEP], [E3, ESTEP], [E3, S], [W1, S]]
    return {"id": "1F", "outline": outline, "spaces": spaces}


# 3F's sign, north up; 2F's rooms go in the same walls.
FX3 = scale((518, W0), (683, W1), (795, WC), (838, CW), (1112, CE), (1157, EC), (1310, E1), (1330, E2),
            (1420, E3))


def floor_2f():
    # The poster's south row, eight rooms, in its proportions.
    widths = [135, 227, 130, 130, 113, 135, 115, 110]
    south = [W0]
    for w in widths:
        south.append(round(south[-1] + w * TOILET_S / sum(widths), 1))
    south[-1] = TOILET_S
    spaces = [
        *SHELL, *BOXES,
        rect("void", CW, NC, CE, CS, name="中庭"),
        *row(N0, NR, [CW, FX3(968), FX3(1093), TOILET_N], [
            L("博雅學部會議室", code="211"),
            L("生命教育心靈空間教室", code="210"),
            L("黃春明研究中心", code="209"),
        ]),
        room(EC, NBOX, E2, CORE, name="黃春明講座教授研究室", code="208"),
        room(W0, WSTEP, 2.2, CS, name="王進發老師研究室"),
        room(2.2, WSTEP, W1, CS, name="林大森老師研究室", code="206"),
        *row(SR, S, south, [
            L("學部長辦公室", note="博雅學部"),
            L("博雅學部", code="201", aka=["經202"]),
            L("陳復老師研究室", code="203"),
            L("廖玉卿老師研究室"),
            L("林德誠老師研究室", code="204"),
            L("社群老師討論室"),
            L("劉文琴老師研究室", code="205"),
            L("鍾鴻銘老師研究室"),
        ]),
    ]
    return {"id": "2F", "outline": OUTLINE, "spaces": spaces, "unit": "博雅學部"}


def floor_3f():
    fx = FX3
    spaces = [
        *SHELL, *BOXES, COURTYARD,
        *row(N0, NR, [CW, fx(992), fx(1110), TOILET_N], [L("普通教室")] * 3),
        room(W1, NC, WC, WSTEP, name="導師休息室"),
        room(EC, NBOX, E2, CORE, name="園藝系景觀研究室"),
        room(W0, WSTEP, W1, CS, name="輔導室"),
        *row(SR, S, [W0, fx(718), CW, fx(1070), TOILET_S], [L("普通教室")] * 3 + [L("機械科辦公室")]),
    ]
    return {"id": "3F", "outline": OUTLINE, "spaces": spaces, "unit": "生物機電工程學系", "aliases": ["生機系"]}


def floor_4f():
    fx = scale((535, W0), (695, W1), (812, WC), (852, CW), (1132, CE), (1175, EC), (1332, E1), (1422, E3))
    spaces = [
        *SHELL, *BOXES, COURTYARD,
        *row(N0, NR, [CW, fx(1012), fx(1071), CE, TOILET_N], [L("教室")] * 4),
        room(W1, NC, WC, WSTEP, name="化工科實驗室"),
        room(EC, NBOX, E2, CORE, name="製圖教室"),
        *row(WSTEP, CS, [W0, fx(615), W1], [L("化工科"), L("化工科辦公室")]),
        *row(SR, S, [W0, W1, CW, fx(1015), EC, TOILET_S],
             [L("PLC實驗室"), L("PLC實驗室"), L("電子工廠"), L("繞線工廠"), L("退休教師聯誼會")]),
    ]
    return {"id": "4F", "outline": OUTLINE, "spaces": spaces}


def floor_5f():
    # Upside down: pixels grow westwards and northwards.
    fx = scale((572, E3), (645, E2), (797, EC), (838, CE), (1103, CW), (1138, WC), (1250, W1), (1418, W0))
    fy = scale((252, S), (378, SR), (422, CS), (553, WSTEP), (790, NC), (828, NR), (942, N0))
    split = fy(640)
    spaces = [
        *SHELL, *BOXES, COURTYARD,
        *row(SR, S, [W0, fx(1265), fx(1110), fx(1033), fx(958), fx(803), TOILET_S], [
            L("視聽教室・物理教室（二）"),
            L("事務組・環安衛生組"),
            L("經管所教師研究室"),
            L("經管所教師研究室"),
            L("經管所教師研究室"),
            L("經管所研討室", note="多功能教室"),
        ]),
        room(W1, CORE, LIFT["rect"][0], CS, name="辦公室"),
        room(W0, WSTEP, fx(1335), CS, name="辦公室"),
        room(fx(1335), WSTEP, W1, CS, name="物理科辦公室"),
        room(W1, NC, WC, WSTEP, name="器材室"),
        room(EC, split, E2, CORE, name="實驗室"),
        room(EC, NBOX, E2, split),
        *row(N0, NR, [CW, fx(1020), fx(942), fx(828), TOILET_N], [
            L("經管所辦公室"), None, L("經管所學生研究室", note="電腦教室・辦公室"), L("經管所行銷調查實驗室"),
        ]),
        room(fx(1020), N0, fx(942), fy(885), name="經管所所長室"),
        room(fx(1020), fy(885), fx(942), NR, name="教師研究室"),
    ]
    return {"id": "5F", "outline": OUTLINE, "spaces": spaces}


def floor_6f():
    # Upside down like 5F. No room in the west column: open hall.
    fx = scale((517, E3), (600, E2), (762, EC), (800, CE), (1072, CW), (1228, W1), (1375, W0))
    fy = scale((238, S), (368, SR), (410, CS), (530, WSTEP), (782, NC), (830, NR), (955, N0))
    split = fy(603)
    spaces = [
        *SHELL, *BOXES, COURTYARD,
        *row(SR, S, [W0, fx(1301), fx(1225), fx(1072), fx(837), TOILET_S], [
            L("主任室"), L("導師室"), L("辦公室"), L("電腦教室"), L("教室", aka=["6B"]),
        ]),
        room(W1, CORE, LIFT["rect"][0], CS, name="辦公室"),
        room(W0, WSTEP, fx(1302), CS, name="會議室"),
        room(fx(1302), WSTEP, W1, CS, name="諮商輔導室"),
        room(EC, split, E2, CORE, name="教室", aka=["6C"]),
        room(EC, NBOX, E2, split, name="教室", aka=["6D"]),
        *row(N0, NR, [CW, fx(920), fx(805), TOILET_N], [L("教室"), L("社團辦公室"), L("幼兒活動室")]),
    ]
    return {"id": "6F", "outline": OUTLINE, "spaces": spaces, "unit": SPACE, "aliases": ["空大"]}


def floor_7f():
    # West up, north on the right: the sign's v runs east, u runs north.
    fx = scale((228, W0), (385, W1), (540, CW), (790, CE), (817, EC), (962, E2), (1005, E3))
    fy = scale((720, S), (828, SR), (870, CS), (1000, WSTEP), (1230, NC), (1250, NR), (1403, N0))
    spaces = [
        *SHELL, *BOXES,
        rect("void", CW, NC, CE, CS),
        room(W0, CS, fx(459), S, name="學生收視閱覽室"),
        room(W0, WSTEP, W1, CS, name="錄音、影帶儲藏室"),
        room(W1, CORE, LIFT["rect"][0], CS, name="辦公室"),
        room(fx(532), SR, fx(710), S, name="圖書館"),
        room(fx(710), SR, TOILET_S, S, name="綜合教室", aka=["7A"]),
        room(EC, NBOX, E2, CORE, name="演講廳", aka=["7B"]),
        *row(N0, NR, [CW, fx(600), fx(758), TOILET_N], [None, L("教室", aka=["7C"]), L("值夜室")]),
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
