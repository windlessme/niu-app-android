#!/usr/bin/env python3
"""Generates app-content/campus-map/shixi.json (時習大樓).

Measured from the evacuation maps on each floor, turned north up (the signs
hang a quarter turn round; 道路 on the 1F sign is the road to the north) and
scaled to the 38.5 × 60 m OpenStreetMap outline. The building is an E open
to the east: rooms along the west spine, a wing at each end, a courtyard
between. 工學院大樓 is to the west. Codes (時) are the signs' own; rooms
the signs leave unnumbered keep only their names.
"""
import json
from pathlib import Path

W, D = 38.5, 60.0
SPINE = (13.6, 18.4)  # the corridor down the spine
N_HALL = (17.5, 20.5)  # north wing corridor
S_HALL = (37.5, 40.5)  # south wing corridor


def rect(kind, x0, y0, x1, y1, code=None, name=None, note=None):
    space = {"kind": kind, "rect": [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)]}
    if code:
        space["code"] = f"時{code}"
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


def room(x0, y0, x1, y1, code=None, name=None, note=None):
    return rect("room", x0, y0, x1, y1, code, name, note)


OUTLINE = [
    [0, 0], [23.0, 0], [23.0, 2.5], [35.5, 3.5], [35.5, 12.5], [38.5, 12.5], [38.5, 23.5], [33.0, 23.5],
    [33.0, N_HALL[1]], [SPINE[1], N_HALL[1]], [SPINE[1], S_HALL[0]], [33.0, S_HALL[0]], [33.0, 35.0],
    [38.5, 35.0], [38.5, 48.0], [35.5, 48.0], [35.5, 57.0], [22.5, 57.0], [22.5, D], [0, D],
]


def shell(spine_from=6.0):
    """Corridors, stairs and lift every upper floor (2F–5F) shares."""
    return [
        rect("corridor", SPINE[0], spine_from, SPINE[1], S_HALL[1]),
        rect("corridor", SPINE[1], N_HALL[0], 33.0, N_HALL[1]),
        rect("corridor", SPINE[1], S_HALL[0], 33.0, S_HALL[1]),
        rect("corridor", 0, S_HALL[0] + 1.0, SPINE[0], S_HALL[1]),
        rect("corridor", 0, 24.5, 4.5, 35.0),
        rect("corridor", 10.0, 24.5, SPINE[0], 35.0),
        # East stair halls, north and south.
        rect("corridor", 33.0, N_HALL[0], 38.5, 23.5),
        rect("corridor", 33.0, 35.0, 38.5, S_HALL[1]),
        rect("stairs", 35.5, 12.5, 38.5, N_HALL[0]),
        rect("stairs", 35.5, S_HALL[1], 38.5, 48.0),
        rect("elevator", 4.5, 24.5, 8.0, 27.6),
        rect("stairs", 4.5, 31.0, 10.0, 35.0),
    ]


def floor_1f():
    spaces = [
        rect("corridor", 12.5, -1.5, 16.5, 4.5),
        rect("corridor", 12.0, 4.5, 15.5, 57.0),
        rect("corridor", 15.5, 14.5, 34.5, 18.5),
        rect("corridor", 15.5, 40.0, 34.5, 41.5),
        rect("corridor", 0, 22.0, 12.0, 32.0),
        rect("corridor", 12.0, 57.0, 17.0, 61.0),
        rect("void", 16.0, 18.5, 26.0, 28.5),
        rect("stairs", 20.0, 28.5, 23.5, 30.5),
        rect("void", 16.0, 30.5, 26.0, 40.0),
        room(0, 0, 12.0, 9.5, name="電腦數值控制實驗室"),
        room(0, 9.5, 12.0, 15.0, name="切削實驗室"),
        rect("restroom", 0, 15.0, 6.5, 18.5, name="女廁"),
        rect("restroom", 0, 18.5, 6.5, 22.0, name="男廁"),
        room(7.5, 18.5, 12.0, 22.0, name="管理員室"),
        rect("elevator", 3.5, 22.5, 7.0, 25.5),
        rect("stairs", 3.5, 28.0, 9.5, 31.5),
        room(0, 32.0, 12.0, 53.5, name="材料實驗室"),
        room(0, 53.5, 4.0, D, name="材料實驗室"),
        room(4.0, 53.5, 8.0, D),
        room(8.0, 53.5, 12.0, D),
        room(15.5, 4.5, 20.5, 14.5, name="智慧製造實驗室"),
        room(20.5, 4.5, 31.5, 14.5, name="智慧製造實驗室"),
        room(31.5, 4.0, 35.0, 8.0, name="儲藏室"),
        rect("stairs", 31.5, 8.5, 35.0, 14.5),
        room(17.0, 41.5, 34.5, 53.5, name="結構實驗室"),
        rect("stairs", 34.5, 41.0, 38.0, 47.0),
    ]
    # The 1F sign is drawn narrower than the floors above; stretch it to the
    # same 38.5 m width.
    for s in spaces:
        x, y, w, h = s["rect"]
        s["rect"] = [round(x * 1.1, 2), y, round(w * 1.1, 2), h]
    outline = [[0, 0], [W, 0], [W, D], [0, D]]
    link = [{"to": "gongxue", "name": "工學院大樓", "at": [0, 27.0], "toward": [-1, 0]}]
    return {"id": "1F", "outline": outline, "spaces": spaces, "links": link}


def floor_2f():
    spaces = [
        *shell(spine_from=8.0),
        room(0, 0, 13.0, 6.0, "202-1", "材料實驗室"),
        room(0, 6.0, 13.0, 17.5, "202", "材料實驗室"),
        room(0, 17.5, 7.0, 21.5, "204", "非破壞檢測實驗室"),
        room(7.0, 18.5, SPINE[0], 22.5, "203", "非破壞檢測實驗室"),
        room(0, 21.5, 7.0, 24.5, "205", "非破壞檢測實驗室"),
        rect("terrace", 13.5, -1.5, 23.0, 2.5, name="戶外露台"),
        room(13.6, 2.5, 18.4, 8.0, "201-3", "智慧機械實驗室"),
        room(18.4, 2.5, 23.0, 8.0, "201-2", "智慧機械實驗室"),
        room(18.4, 8.0, 22.5, N_HALL[0], "201-1", "智慧機械實驗室"),
        room(22.5, 3.0, 35.5, N_HALL[0], "201", "智慧機械實驗室"),
        room(4.5, 27.6, 10.0, 31.0, "211"),
        rect("restroom", 0, 35.0, 4.5, 38.5, name="廁所"),
        room(9.0, 35.0, SPINE[0], 38.5),
        rect("terrace", 22.0, 22.0, 30.0, 32.0, name="戶外露台"),
        room(0, S_HALL[1], 13.0, 52.0),
        room(0, 52.0, 13.5, D),
        room(13.6, 52.5, 22.5, 57.0),
        room(SPINE[1], S_HALL[1], 22.0, 52.5),
        room(22.0, S_HALL[1], 35.5, 52.5),
        rect("terrace", 13.6, 57.0, 22.5, 61.5, name="戶外露台"),
    ]
    return {"id": "2F", "outline": OUTLINE, "spaces": spaces}


def floor_3f():
    spaces = [
        *shell(),
        room(0, 0, SPINE[0], 5.5, name="液氣壓實驗室"),
        room(0, 5.5, SPINE[0], 15.0, name="專題製作室"),
        room(0, 15.0, SPINE[0], 24.5, name="理論與計算流力實驗室"),
        room(13.6, 0, 18.4, 6.0, name="熱流實驗室"),
        room(18.4, 0, 23.0, 6.0, name="熱流實驗室"),
        room(18.4, 6.0, 35.5, N_HALL[0], name="熱流實驗室"),
        rect("void", -2.5, 24.5, 4.5, 35.0),
        room(4.5, 27.6, 10.0, 31.0, name="儲藏室"),
        rect("restroom", 0, 35.0, 4.5, 38.5, name="廁所"),
        room(9.0, 35.0, SPINE[0], 38.5, name="儲藏室"),
        room(0, S_HALL[1], SPINE[0], D, name="先進製造與功能材料實驗室（一）"),
        room(SPINE[0], S_HALL[1], SPINE[1], 53.0, name="自動化實驗室"),
        room(SPINE[1], S_HALL[1], 32.5, 53.0, name="自動化實驗室"),
        room(32.5, 44.5, 35.5, 53.0, name="先進製造與功能材料實驗室（二）"),
        room(SPINE[0], 53.0, 22.5, D, name="自動化實驗室"),
    ]
    return {"id": "3F", "outline": OUTLINE, "spaces": spaces}


def floor_4f():
    spaces = [
        *shell(spine_from=16.0),
        rect("terrace", 0, 0, 9.5, 6.0, name="戶外露台"),
        {"kind": "room", "code": "時403", "name": "化學實驗室（二）",
         "polygon": [[9.5, 0], [SPINE[0], 0], [SPINE[0], 19.5], [0, 19.5], [0, 6.0], [9.5, 6.0]]},
        room(0, 19.5, 9.0, 24.5, name="藥品室"),
        room(9.0, 21.0, SPINE[0], 24.5, name="電器室"),
        room(13.6, 0, 18.4, 6.0),
        room(18.4, 0, 23.0, 6.0, name="藥品室"),
        room(14.4, 6.0, 18.4, 10.5, name="器材室"),
        room(14.4, 10.5, 18.4, 16.0, "402", "教師準備室"),
        room(18.4, 6.0, 35.5, N_HALL[0], "401", "化學實驗室（一）"),
        rect("void", -2.5, 24.5, 4.5, 35.0),
        room(4.5, 27.6, 10.0, 31.0, "404", "綠色材料實驗室"),
        rect("restroom", 0, 35.0, 4.5, 38.5, name="廁所"),
        room(9.0, 35.0, SPINE[0], 38.5, name="儲藏室"),
        room(0, S_HALL[1], 5.5, 44.0, "405"),
        room(5.5, S_HALL[1], SPINE[0], 44.0, name="實驗室"),
        room(0, 44.0, 5.5, 49.5, name="教師研究室"),
        room(0, 49.5, 5.5, 55.0, name="儲藏室"),
        room(5.5, 44.0, SPINE[0], 55.0, "406", "綠色科技與永續發展實驗室"),
        rect("terrace", 0, 55.0, SPINE[0], D, name="戶外露台"),
        room(SPINE[0], 55.0, 22.5, D, name="退休教師研究室"),
        room(SPINE[1], S_HALL[1], 30.0, 55.0, "407"),
        room(30.0, S_HALL[1], 35.5, 48.0, name="GC 實驗室"),
        room(30.0, 48.0, 35.5, 55.0, name="AA 實驗室"),
    ]
    return {"id": "4F", "outline": OUTLINE, "spaces": spaces}


def floor_5f():
    spaces = [
        *shell(spine_from=N_HALL[0]),
        rect("corridor", SPINE[0], N_HALL[0], SPINE[1], N_HALL[1]),
        rect("terrace", 13.5, 0.5, 22.5, 6.5, name="戶外露台"),
        room(0, 6.5, SPINE[0], 18.5, "502", "空氣污染防制與奈米量測及應用實驗室"),
        room(0, 18.5, SPINE[0], 22.0, "503"),
        rect("restroom", 0, 22.0, 8.5, 24.5, name="女廁"),
        room(8.5, 22.0, SPINE[0], 24.5, "503-1", "助理辦公室"),
        room(SPINE[0], 6.5, 24.5, N_HALL[0], "501", "廢棄物資材化實驗室"),
        room(24.5, 6.5, 32.0, N_HALL[0], "501-1", "先進能源與分子環境善用實驗室"),
        room(32.0, 7.5, 35.5, 13.0, name="教師研究室"),
        rect("void", -2.5, 24.5, 4.5, 35.0),
        room(4.5, 27.6, 10.0, 31.0, "504", "助理研究生室"),
        rect("restroom", 0, 35.0, 8.5, 38.5, name="男廁"),
        room(9.0, 35.0, SPINE[0], 38.5, "505", "顯微鏡室"),
        room(0, S_HALL[1] + 1.5, SPINE[0], 57.0, "506", "吸附劑及觸媒材料研究室"),
        room(SPINE[1], S_HALL[1], 31.0, 57.0, "507", "水污染防制及水資源再生實驗室"),
        room(31.0, 50.0, 35.5, 57.0, name="教師研究室"),
        rect("terrace", 13.5, 57.0, 22.5, 61.5, name="戶外露台"),
    ]
    link = [{"to": "gongxue", "name": "工學院大樓", "at": [0, 40.3], "toward": [-1, 0]}]
    return {"id": "5F", "outline": OUTLINE, "spaces": spaces, "links": link}


def main():
    building = {
        "id": "shixi",
        "name": "時習大樓",
        "unit": "m",
        "floors": [f() for f in (floor_1f, floor_2f, floor_3f, floor_4f, floor_5f)],
    }
    for floor in building["floors"]:
        codes = [s["code"] for s in floor["spaces"] if "code" in s]
        assert len(codes) == len(set(codes)), (floor["id"], codes)
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/shixi.json", root / "mobile/assets/campus_map/shixi.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
