#!/usr/bin/env python3
"""Generates app-content/campus-map/gongxue.json (工學院大樓).

Measured from the evacuation maps on each floor. The signs are drawn at
different aspect ratios and turned different ways (1F a quarter turn, 3F
upside down, B1 a quarter turn the other way), so each photo was fitted to
the structural columns: a 6 × 6 bay grid every floor shares. East–west the
bays are 7.2 m; north–south the building is 51.4 m (OpenStreetMap) split as
the signs agree. North is up, 時習大樓 is east.

B1 is the plant floor, 1F the college offices, lecture hall and glass lobby,
2F civil engineering around a courtyard over the lecture hall. 3F–6F share
one E-shaped shell open to the east.
"""
import json
from pathlib import Path

W, D = 43.2, 51.4  # column lines, metres
X = [i * 7.2 for i in range(7)]  # 0 7.2 14.4 21.6 28.8 36 43.2
N_ROW = (0, 8.8)  # north rooms
N_HALL = (8.8, 11.7)  # north corridor
WEST = 7.7  # west rooms end here
W_HALL = (7.7, 10.2)  # west corridor
MID = 10.2  # middle rooms start here
S_MID = (33.6, 38.8)  # rooms north of the south corridor
S_HALL = (38.8, 42.3)
S_ROW = (42.3, D)
SW = 6.8  # service lift and stairs west of here, south row


def rect(kind, x0, y0, x1, y1, code=None, name=None, note=None):
    space = {"kind": kind, "rect": [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)]}
    return labelled(space, code, name, note)


def poly(kind, points, code=None, name=None, note=None):
    space = {"kind": kind, "polygon": [[round(x, 2), round(y, 2)] for x, y in points]}
    return labelled(space, code, name, note)


def labelled(space, code, name, note):
    if code:
        space["code"] = f"工{code}"
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


def room(x0, y0, x1, y1, code=None, name=None, note=None):
    return rect("room", x0, y0, x1, y1, code, name, note)


def row(y, edges, labels):
    """Rooms side by side between edges, west to east."""
    assert len(edges) == len(labels) + 1, (edges, labels)
    out = []
    for (a, b), label in zip(zip(edges, edges[1:]), labels):
        code, name, *note = label
        out.append(room(a, y[0], b, y[1], code, name, *note))
    return out


def column(x, edges, labels):
    """Rooms stacked between edges, north to south."""
    assert len(edges) == len(labels) + 1, (edges, labels)
    out = []
    for (a, b), label in zip(zip(edges, edges[1:]), labels):
        code, name, *note = label
        out.append(room(x[0], a, x[1], b, code, name, *note))
    return out


def core():
    """Lifts and stairs east of the north corridor, every floor."""
    return [
        rect("stairs", 28.8, 15.3, 31.0, 17.8),
        rect("elevator", 31.0, 15.3, 33.35, 17.8),
        rect("elevator", 33.35, 15.3, 35.7, 17.8),
        rect("stairs", 28.8, 17.8, 36.7, 20.3),
    ]


def southwest():
    """Service lift and stairs in the south-west corner, every floor."""
    return [
        rect("corridor", 0, S_ROW[0], SW, 50),
        rect("elevator", 0.8, 43.0, 3.7, 45.0),
        rect("stairs", 0, 45.0, SW, 50),
    ]


def services(spare):
    """The west block between the west rooms and the south corridor, 2F–6F:
    men's north, women's south, the accessible toilet in the south-east."""
    return [
        room(0, 27.7, 5.0, 31.2, name="資訊機房"),
        room(5.0, 27.7, WEST, 31.2, name="茶水間"),
        rect("restroom", 0, 31.2, WEST, 34.5, name="男廁"),
        rect("restroom", 0, 34.5, 5.3, S_MID[1], name="女廁"),
        room(5.3, 34.5, WEST, 36.3, name=spare),
        rect("restroom", 5.3, 36.3, WEST, S_MID[1], name="無障礙廁所"),
    ]


SHELL_OUTLINE = [
    [0, 0], [W, 0], [W, 18.0], [36.7, 18.0], [36.7, 20.3], [28.4, 20.3], [28.4, 17.8],
    [14.4, 17.8], [14.4, S_MID[0]], [W, S_MID[0]], [W, D], [SW, D], [SW, 50], [0, 50],
]


def shell():
    """Corridors, core and services every typical floor (3F–6F) shares."""
    return [
        rect("corridor", 0, N_HALL[0], W, N_HALL[1]),
        rect("corridor", 28.8, N_HALL[1], W, 18.0),
        rect("corridor", W_HALL[0], N_HALL[1], W_HALL[1], S_MID[1]),
        rect("corridor", 0, S_HALL[0], W, S_HALL[1]),
        *core(),
        *southwest(),
    ]


def to_shixi(y):
    return [{"to": "shixi", "name": "時習大樓", "at": [W, y], "toward": [1, 0]}]


def floor_b1():
    spaces = [
        rect("corridor", 0, N_HALL[0], 14.4, 11.3),
        rect("corridor", 28.8, N_HALL[0], W, 14.5),
        rect("corridor", 11.6, 11.3, 14.4, S_HALL[1]),
        rect("corridor", 14.4, 11.3, 28.4, 14.0),
        rect("corridor", 39.8, 14.5, W, 39.0),
        rect("corridor", 28.4, 14.5, 28.8, 39.0),
        rect("corridor", 0, 39.0, W, S_HALL[1]),
        rect("stairs", 28.8, 14.5, 31.0, 20.0),
        rect("elevator", 31.0, 14.5, 33.1, 17.5),
        rect("elevator", 33.1, 14.5, 35.2, 17.5),
        rect("stairs", 31.0, 17.5, 33.5, 20.0),
        room(35.3, 14.5, 39.8, 17.8, "B02", "機房"),
        room(0, 0, 4.0, N_ROW[1], name="發電機室"),
        room(4.0, 0, 8.0, N_ROW[1], name="消防機房"),
        room(8.0, 0, 14.4, N_ROW[1], name="自來水水箱"),
        room(14.4, 0, 28.8, 11.3, "B05", "材料實驗室（1）"),
        room(28.8, 0, 36.0, N_ROW[1], "B03", "材料準備室"),
        room(36.0, 0, W, N_ROW[1], "B01", "研討室 B01"),
        room(0, 11.3, 7.0, 18.0, name="廢水機房"),
        room(7.0, 11.3, 11.6, 18.0, name="生活污水機房"),
        room(0, 18.0, 11.6, 29.4, name="自設高壓配電室"),
        rect("restroom", 0, 29.4, 7.0, 33.2, name="女廁"),
        rect("restroom", 0, 33.2, 7.0, 37.0, name="男廁"),
        room(7.0, 33.8, 9.0, 37.6, name="資源回收"),
        room(9.0, 35.0, 11.6, 37.6, "B08", "茶水間"),
        room(0, 37.0, 5.7, 39.0, name="網路機房"),
        room(14.4, 14.0, 16.4, 17.4, "B06", "機房"),
        room(18.4, 14.0, 28.4, 17.6, "B04", "儲藏室"),
        room(14.4, 17.6, 21.6, 33.6, "B12", "儲藏室"),
        room(21.6, 17.6, 28.4, 33.6, name="機房"),
        room(14.4, 33.8, 16.4, 37.4, "B10", "儲藏室"),
        room(18.4, 33.8, 24.3, 39.0, "B14", "儲藏室"),
        room(24.3, 33.8, 28.4, 39.0, "B16", "網路機房"),
        room(28.4, 20.2, 39.8, 26.0, "B20", "系學會辦公室"),
        room(28.4, 26.0, 39.8, 39.0, "B18", "多功能教室"),
        *southwest(),
        room(7.7, S_ROW[0], 21.2, D, "B07", "單元操作實驗室"),
        *row(S_ROW, [21.2, 25.2, 28.8, 32.4, 36.0, 39.6, W], [
            ("B09", "單操準備室"),
            ("B11", "先進粉末技術實驗室"),
            ("B13", "先進粉末技術實驗室"),
            ("B15", "分離及界面科技實驗室"),
            ("B17", "觸媒及反應工程實驗室"),
            ("B19", "材料實驗室（2）"),
        ]),
    ]
    return {"id": "B1", "outline": [[0, 0], [W, 0], [W, D], [0, D]], "spaces": spaces}


def floor_1f():
    spaces = [
        # The glass lobby fills the east half from the north entrance down.
        rect("corridor", 28.8, 0, W, 39.8),
        rect("corridor", 14.4, 9.0, 28.8, 11.5),
        rect("corridor", 0, 11.5, 28.8, 14.0),
        rect("corridor", WEST - 0.5, 14.0, 14.0, 17.8),
        rect("corridor", 9.8, 17.8, 14.0, 37.0),
        rect("corridor", 9.8, 36.3, 28.8, 39.8),
        rect("corridor", 0, 37.0, 9.8, 39.8),
        rect("corridor", 14.0, 14.0, 28.4, 17.8),
        *core(),
        *southwest(),
        room(0, 0, 7.2, 4.8, "106-1"),
        room(0, 4.8, 7.2, 11.5, "106", "教職員聯誼室"),
        room(7.2, 0, 14.4, 11.5, "105", "院會議室"),
        room(14.4, 0, 21.6, 9.0, "102", "院長室"),
        room(21.6, 0, 28.8, 9.0, "101", "工學院辦公室／副院長室"),
        room(0, 14.0, 7.2, 17.8, "107", "綠科碩專班"),
        room(0, 17.8, 9.8, 29.5, "108", "綠色科技研發中心"),
        rect("stairs", 14.2, 14.2, 17.0, 17.6),
        room(20.6, 14.4, 22.8, 17.6, "103", "管理員室"),
        room(14.0, 17.8, 28.4, 33.3, name="演講廳", note="126 人"),
        rect("stairs", 18.4, 33.3, 21.0, 36.2),
        room(21.0, 33.3, 28.4, 36.3, "116", "中央監控室"),
        rect("restroom", 0, 29.5, 6.8, 33.2, name="女廁"),
        rect("restroom", 6.8, 29.5, 9.8, 31.6, name="無障礙廁所"),
        rect("restroom", 0, 33.2, 6.8, 37.0, name="男廁"),
        room(6.8, 33.7, 8.3, 35.3, "109", "控制室"),
        room(8.3, 33.7, 9.8, 35.3, "110", "沖洗間"),
        *row((39.8, D), [WEST - 0.5, 14.4, 21.6, 28.8, 35.9, W], [
            ("111", "碩專班研討室三"),
            ("112", "碩專班研討室二"),
            ("113", "碩專班研討室一"),
            ("114", "研討室二"),
            ("115", "研討室一"),
        ]),
    ]
    return {"id": "1F", "outline": [[0, 0], [W, 0], [W, D], [0, D]], "spaces": spaces, "links": to_shixi(29.7)}


def floor_2f():
    spaces = [
        rect("corridor", 0, N_HALL[0], W, N_HALL[1]),
        rect("corridor", 28.8, N_HALL[1], W, 18.0),
        rect("corridor", W_HALL[0], N_HALL[1], W_HALL[1], S_MID[1]),
        rect("corridor", MID, 22.7, 14.4, 28.3),
        rect("corridor", 0, S_HALL[0], W, S_HALL[1]),
        *core(),
        *southwest(),
        # The courtyard sits on the lecture hall; the grid east of it is the
        # glass lobby's roof.
        rect("terrace", 15.8, 20.0, 29.2, 31.6, name="中庭"),
        rect("void", 29.3, 20.3, W, S_MID[0]),
        *row(N_ROW, [0, 3.67, 7.17, 10.73, 14.33, 17.93, 21.6, 28.8], [
            ("211", "林威廷教師研究室"),
            ("210", "黃春嘉教師研究室"),
            ("209", "陳桂鴻教師研究室"),
            ("208", "陳冠宏教師研究室"),
            ("206", "陳傑教師研究室"),
            ("205", "江啟明教師研究室"),
            ("204", "會議室"),
        ]),
        room(28.8, 0, 31.9, 5.8, "202-1", "儲藏室"),
        poly("room", [(31.9, 0), (39.6, 0), (39.6, N_ROW[1]), (28.8, N_ROW[1]), (28.8, 5.8), (31.9, 5.8)],
             "202", "土木工程學系辦公室"),
        room(39.6, 0, W, N_ROW[1], "201", "系主任辦公室"),
        room(0, N_HALL[1], WEST, 17.8, "212", "測量與空間資訊研究室"),
        room(MID, N_HALL[1], 14.4, 17.8, "207", "工程研討室"),
        room(14.4, N_HALL[1], 28.8, 17.8, "203", "營建自動化教室"),
        room(0, 17.8, WEST, 25.3, "213", "工程研討室"),
        room(0, 25.3, WEST, 27.7, name="儲藏室"),
        room(MID, 17.8, 14.4, 22.7, "214", "討論室"),
        room(MID, 28.3, 14.4, S_MID[1], "216", "圖書室"),
        *services("工具間"),
        *row(S_MID, [14.4, 21.6, 28.8, 35.9, W], [
            ("219", "營建管理研究室"),
            ("222", "水資源工程研究室"),
            ("225", "大地工程與材料工程研究室"),
            ("228", "結構工程研究室"),
        ]),
        *row(S_ROW, [SW, 10.5, 14.33, 17.93, 21.6, 25.17, 28.83, 32.33, 35.93, 39.6, W], [
            ("217", "教師研究室"),
            ("218", "郭品含教師研究室"),
            ("220", "曾浩璽教師研究室"),
            ("221", "楊炫智教師研究室"),
            ("223", "王志煌教師研究室"),
            ("224", "吳清森教師研究室"),
            ("226", "歐陽慧濤教師研究室"),
            ("227", "鄭安教師研究室"),
            ("229", "徐輝明教師研究室"),
            ("230", "趙紹錚教師研究室"),
        ]),
    ]
    return {"id": "2F", "outline": [[0, 0], [W, 0], [W, D], [SW, D], [SW, 50], [0, 50]], "spaces": spaces}


def typical(level, spaces, link_y=40.5):
    return {"id": level, "outline": SHELL_OUTLINE, "spaces": [*shell(), *spaces], "links": to_shixi(link_y)}


def floor_3f():
    return typical("3F", [
        room(0, 0, 14.4, N_ROW[1], "311", "工學院智慧工程整合實驗室"),
        *row(N_ROW, [14.4, 17.9, 21.6, 28.8], [
            ("309", "資訊機房"),
            ("307", "機器人暨電學實驗室"),
            ("304", "機器人暨電學實驗室"),
        ]),
        room(28.8, 0, 31.9, 5.8, "302-1", "資料室"),
        poly("room", [(31.9, 0), (39.6, 0), (39.6, N_ROW[1]), (28.8, N_ROW[1]), (28.8, 5.8), (31.9, 5.8)],
             "302", "機械系辦公室"),
        room(39.6, 0, W, N_ROW[1], "301", "系主任辦公室"),
        *row((N_HALL[1], 17.8), [MID, 14.4, 18.0, 21.6, 25.2, 28.8], [
            ("310", "討論室"),
            ("308", "施景瑞教師研究室"),
            ("306", "教師研究室"),
            ("305", "陳正虎教師研究室"),
            ("303", "鍾政英教師研究室"),
        ]),
        *column((0, WEST), [N_HALL[1], 17.8, 27.7], [
            ("312", "兼任教師研究室"),
            ("315", "會議室"),
        ]),
        *column((MID, 14.4), [17.8, 23.2, 28.3, S_MID[0]], [
            ("313", "林彥宏教師研究室"),
            ("314", "方治國教師研究室"),
            ("317", "梁瑞庭教師研究室"),
        ]),
        *services("資源回收"),
        *row(S_MID, [MID, 14.3, 18.1, 21.6, 25.2, 28.8, 32.3, 35.9, 39.5, W], [
            ("319", "系學會辦公室"),
            ("320", "簡忠漢教師研究室"),
            ("322", "王金燦教師研究室"),
            ("323", "梁煥昌教師研究室"),
            ("324", "王宜達教師研究室"),
            ("326", "林岳陞教師研究室"),
            ("328", "林宗鴻教師研究室"),
            ("329", "沈立宗教師研究室"),
            ("330", "陳松郁教師研究室"),
        ]),
        *row(S_ROW, [SW, 14.4, 21.6, 28.8, 36.0, W], [
            ("318", "學生交誼廳"),
            ("321", "課研室（一）"),
            ("325", "課研室（二）"),
            ("327", "課研室（三）"),
            ("331", "課研室（四）"),
        ]),
    ])


def floor_4f():
    return typical("4F", [
        *row(N_ROW, [0, 7.2, 14.4, 21.6, 28.8, 39.7, W], [
            ("409", "薛方杰教授研究室"),
            ("408", "何武璋教授研究室"),
            ("406", "空間資訊實驗室"),
            ("404", "多功能會議室"),
            ("402", "所辦公室"),
            ("401", "所長辦公室"),
        ]),
        *row((N_HALL[1], 17.8), [MID, 14.4, 21.6, 28.8], [
            ("407", "研討室"),
            ("405", "永續環境與行為實驗室"),
            ("403", "休閒景觀規劃實驗室"),
        ]),
        room(0, N_HALL[1], WEST, 27.7, "410", "多媒體視聽室"),
        *column((MID, 14.4), [17.8, 23.0, 28.3, S_MID[0]], [
            ("411", "創意概念交流室"),
            ("412", "創意概念交流室"),
            ("414", "討論室"),
        ]),
        *services("工具間"),
        *row(S_MID, [MID, 14.4, 21.6, 28.8, 36.0, W], [
            ("415", "研究生研究室"),
            ("417", "研究生研究室"),
            ("419", "地景敘事與設計工作室"),
            ("421", "永續性建築環境實驗室"),
            ("423", "BIM 發展研究室"),
        ]),
        *row(S_ROW, [SW, 14.4, 21.6, 28.8, 36.0, W], [
            ("416", "集體研討室"),
            ("418", "郭建慧教授研究室"),
            ("420", "張家瑞教授研究室"),
            ("422", "徐輝明教授研究室"),
            ("424", "謝宏仁教授研究室"),
        ]),
    ])


def floor_5f():
    return typical("5F", [
        *row(N_ROW, [0, 3.67, 7.17, 10.73, 14.33, 17.93, 21.6, 25.17, 28.83, 32.33, 35.93, 39.5, W], [
            ("512", "張章堂博士"),
            ("511", "邱應志博士"),
            ("510", "劉鎮宗博士"),
            ("509", "李元陞博士"),
            ("508", "邱求三博士"),
            ("507", "林凱隆博士"),
            ("506", "陳文興博士"),
            ("505", "謝哲隆博士"),
            ("504", "黃鼎荃博士"),
            ("503", "張益誠博士"),
            ("502", "陳薇羽博士"),
            ("501", "楊汶達博士"),
        ]),
        *row((N_HALL[1], 17.8), [MID, 17.9, 28.8], [
            ("514", "研討室一"),
            ("513", "系辦公室"),
        ]),
        rect("terrace", 38.5, 15.8, W, 18.0, name="陽台"),
        *column((0, WEST), [N_HALL[1], 15.7, 23.3, 27.7], [
            ("515", "系學會"),
            ("516", "系會議室"),
            ("516-1", "儲藏室"),
        ]),
        *column((MID, 14.4), [17.8, 25.3, S_MID[0]], [
            ("518", "研討室二"),
            ("519", "研究休息室"),
        ]),
        *services("置物間"),
        *row(S_MID, [MID, 14.4, 28.8, W], [
            ("520", "實驗器材室", "劉鎮宗博士"),
            ("521", "環境（監測）資通技術應用暨管理決策分析實驗室", "張益誠博士"),
            ("522", "土壤環境科學實驗室", "劉鎮宗博士"),
        ]),
        *row(S_ROW, [SW, 10.3, 14.4, 28.8, W], [
            ("525-1", "綠色材料精密儀器室", "林凱隆博士"),
            ("525", "先進能源與分子環境精密儀器室", "謝哲隆博士"),
            ("524", "共同實驗室"),
            ("523", "環境微生物實驗室", "邱應志博士"),
        ]),
    ])


def floor_6f():
    return typical("6F", [
        room(0, 0, 14.4, N_ROW[1], "615", "物理化學實驗室"),
        *row(N_ROW, [14.4, 17.9, 21.6, 25.2, 28.8, 32.9, 39.6, W], [
            ("613", "藥品器材室"),
            ("611", "材料與永續能源實驗室"),
            ("609", "熱性質分析實驗室"),
            ("607", "機械性質分析實驗室"),
            ("605", "系辦公室"),
            ("603", "系會議室"),
            ("601", "系主任辦公室"),
        ]),
        room(MID, N_HALL[1], 14.4, 15.7, "610", "小型討論室"),
        *row((N_HALL[1], 17.8), [14.4, 18.0, 21.6, 25.2, 28.8], [
            ("608", "張世航老師教研室"),
            ("606", "吳宏達老師教研室"),
            ("604", "范國泰老師教研室"),
            ("602", "黃書賢老師教研室"),
        ]),
        *column((0, WEST), [N_HALL[1], 15.8, 19.6, 23.4, 27.7], [
            ("617", "儀器分析實驗室 1"),
            ("619", "儀器分析實驗室 2"),
            ("621", "儀器分析實驗室 3"),
            ("623", "儀器分析實驗室 4"),
        ]),
        *column((MID, 14.4), [15.7, 21.3, 25.5, 30.5, 35.7, S_MID[1]], [
            ("612", "陳博彥老師教研室"),
            ("614", "林松華老師教研室"),
            ("616", "薛仲娟老師教研室"),
            ("618", "陳建樺老師教研室"),
            ("620", "公用設備室"),
        ]),
        *[s for s in services("資源回收") if s.get("name") != "茶水間"],
        room(5.0, 27.7, WEST, 31.2, "625", "茶水間"),
        *row(S_MID, [14.4, 18.0, 21.6, 25.2, 28.8, 32.4, 36.0, 39.6, W], [
            ("622", "賴森茂老師教研室"),
            ("624", "韓錦鈴老師教研室"),
            ("626", "劉冠良老師教研室"),
            ("628", "陳華偉老師教研室"),
            ("630", "王修璇老師教研室"),
            ("632", "林芳如老師教研室"),
            ("634", "蔡尚恬老師教研室"),
            ("636", "郭文堯老師教研室"),
        ]),
        *row(S_ROW, [SW, 14.4, 21.6, 28.8, 36.0, W], [
            ("627", "孔洞材料實驗室"),
            ("629", "香妝生醫與綠色循環材料實驗室"),
            ("631", "表面科學實驗室"),
            ("633", "分離及介面科技實驗室"),
            ("635", "有機材料化學實驗室"),
        ]),
    ])


# The lift's directory: who each floor belongs to, with the short names
# people search by. The signs only say 系辦公室, so those rooms get the unit
# as a note.
UNITS = {
    "1F": ("院辦公室・碩專班・自學中心・研究群", [], []),
    "2F": ("土木工程學系", ["土木系", "土木"], ["201", "202", "202-1"]),
    "3F": ("機械與機電工程學系", ["機械系", "機電系", "機械", "機電"], ["301", "302", "302-1", "312", "315", "319"]),
    "4F": ("建築與永續規劃研究所", ["建築所", "建築", "永續規劃"], ["401", "402"]),
    "5F": ("環境工程學系", ["環工系", "環工", "環境工程"], ["513", "515", "516", "516-1"]),
    "6F": ("化學工程與材料工程學系", ["化材系", "化工系", "化材", "化工"], ["601", "603", "605"]),
}


def main():
    building = {
        "id": "gongxue",
        "name": "工學院大樓",
        "unit": "m",
        "floors": [f() for f in (floor_b1, floor_1f, floor_2f, floor_3f, floor_4f, floor_5f, floor_6f)],
    }
    for floor in building["floors"]:
        if floor["id"] in UNITS:
            unit, aliases, offices = UNITS[floor["id"]]
            floor["unit"] = unit
            floor["aliases"] = aliases
            for space in floor["spaces"]:
                if space.get("code", "")[1:] in offices:
                    assert "note" not in space, space
                    space["note"] = unit
        codes = [s["code"] for s in floor["spaces"] if "code" in s]
        assert len(codes) == len(set(codes)), (floor["id"], codes)
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/gongxue.json", root / "mobile/assets/campus_map/gongxue.json"):
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
