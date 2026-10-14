#!/usr/bin/env python3
"""Generates app-content/campus-map/dianzi.json (電資二館).

Measured from the evacuation maps on each floor, matched floor to floor by
the structural columns (four lines along the building, about 10 m apart)
and scaled to the 47.2 m OpenStreetMap outline. The signs face south, so
each floor is drawn as the sign shows it and then turned half round: north
up, the toilets at the west end, the lift and 2F bridge to 格致大樓 north.
The 3F and 4F signs hang a quarter turn round, so they were turned to
match. Room numbers on 1F and 2F were written on the photos by the user;
3F and 4F names come from the door signs.
"""
import json
from pathlib import Path

W = 47.2
D = 19.0  # deepest point of any floor, where the 2F bridge leaves
GEZHI = "格致大樓（電資學院）"


def flipped(floor):
    """Turns a floor drawn as the signs show it half round, north up: the
    signs face south, and the 2F bridge to 格致大樓 leaves northwards."""
    def pt(p):
        return [round(W - p[0], 2), round(D - p[1], 2)]

    for s in floor["spaces"]:
        if "rect" in s:
            x, y, w, h = s["rect"]
            s["rect"] = [round(W - x - w, 2), round(D - y - h, 2), w, h]
        else:
            s["polygon"] = [pt(p) for p in s["polygon"]]
    floor["outline"] = [pt(p) for p in floor["outline"]]
    for link in floor.get("links", []):
        link["at"] = pt(link["at"])
        link["toward"] = [-link["toward"][0], -link["toward"][1]]
    return floor


def rect(kind, x0, y0, x1, y1, code=None, name=None, note=None):
    space = {"kind": kind, "rect": [round(x0, 2), round(y0, 2), round(x1 - x0, 2), round(y1 - y0, 2)]}
    if code:
        space["code"] = f"資{code}"
    if name:
        space["name"] = name
    if note:
        space["note"] = note
    return space


def room(x0, y0, x1, y1, code=None, name=None, note=None):
    return rect("room", x0, y0, x1, y1, code, name, note)


def toilets(x0, x1, men, women, accessible):
    """East toilets, north to south: men's, women's, accessible."""
    return [
        rect("restroom", x0, *men[:1], x1, men[1], name="男廁"),
        rect("restroom", x0, *women[:1], x1, women[1], name="女廁"),
        rect("restroom", x0, *accessible[:1], x1, accessible[1], name="無障礙廁所"),
    ]


def floor_1f():
    spaces = [
        rect("corridor", 0.5, 0.5, 8.0, 11.5),
        rect("corridor", 0.5, 11.5, 44.5, 16.3),
        rect("corridor", 41.4, 1.3, 43.9, 11.5),
        rect("elevator", 22.8, 14.5, 25.6, 17.3),
        rect("stairs", 8.9, 15.0, 15.2, 16.9),
        rect("stairs", 44.3, 8.1, 47.6, 13.0),
        room(8.0, 1.2, 20.9, 11.5, "103", "靜態展示室"),
        room(20.9, 1.2, 35.1, 11.5, "102", "互動展示室"),
        room(35.1, 1.3, 41.3, 4.5, name="消防泵浦室"),
        room(35.1, 4.5, 37.3, 7.6, name="儲藏室"),
        room(37.3, 4.5, 41.3, 7.6, name="配電室"),
        room(35.4, 7.7, 41.4, 11.5, "101", "設備機房／電信室"),
        *toilets(43.9, 47.0, (1.3, 3.6), (3.6, 5.8), (5.8, 7.7)),
    ]
    outline = [[0.5, 0.3], [47.6, 0.3], [47.6, 13.0], [44.5, 16.3], [11.0, 18.0], [4.5, 16.3], [0.5, 12.8]]
    return {"id": "1F", "outline": outline, "spaces": spaces}


def floor_2f():
    spaces = [
        rect("corridor", 4.1, 11.6, 44.3, 13.5),
        rect("corridor", 9.7, 13.5, 29.4, 14.8),
        rect("corridor", 4.1, 4.9, 4.6, 11.6),
        rect("corridor", 0, 4.9, 4.1, 6.7),
        rect("corridor", 42.3, 1.4, 44.1, 11.6),
        rect("elevator", 21.8, 14.4, 24.3, 17.2),
        rect("stairs", 11.5, 14.3, 17.7, 16.2),
        rect("stairs", 44.1, 8.7, 47.2, 12.6),
        # The walkway past 201 and 202 is the bridge to 格致大樓.
        rect("corridor", 29.5, 13.5, 33.0, 19.0),
        # The department's three rooms share one number, 資205.
        room(0, 0.9, 4.6, 4.9, "205", "系主任辦公室"),
        room(0, 6.7, 4.1, 14.4, "205", "會議室"),
        room(4.6, 0.9, 9.7, 11.4, "205", "系辦公室"),
        room(9.7, 0, 30.5, 11.6, "204", "電腦教室"),
        room(30.5, 0, 42.3, 11.6, "203", "邏輯設計實驗室"),
        room(33.1, 13.6, 38.5, 15.3, "202", "儲藏室"),
        room(33.1, 15.3, 38.5, 18.8, "201", "控制研究室"),
        *toilets(44.1, 47.2, (1.4, 3.4), (3.4, 6.0), (6.0, 8.3)),
    ]
    outline = [[0, 0.5], [9.7, 0.5], [9.7, 0], [42.8, 0], [42.8, 1.2], [47.2, 1.2], [47.2, 13.5],
               [38.7, 13.5], [38.7, 19.0], [29.4, 19.0], [29.4, 14.8], [9.7, 14.8], [9.7, 14.4], [0, 14.4]]
    link = [{"to": "gezhi", "name": GEZHI, "at": [31.25, 19.0], "toward": [0, 1]}]
    return {"id": "2F", "outline": outline, "spaces": spaces, "links": link}


def upper(level, rooms_n, rooms_s, toilet_rows, east_stairs, south):
    """3F and 4F: rooms either side of a corridor along the building, the
    lift lobby on the south side."""
    xs = [44.0, 37.1, 31.5, 26.0, 21.5, 15.5, 9.3, 3.0]  # room walls, east to west; 26–21.5 is the lift hall
    spaces = [
        rect("corridor", 3.0, 4.6, 44.0, 6.6),
        rect("corridor", 44.0, 1.9, 45.8, east_stairs[1]),
        rect("corridor", 21.5, 0, 26.0, 4.6),
        rect("corridor", 21.5, 6.6, 26.0, 11.3),
        rect("corridor", 12.0, 11.3, 26.0, 14.3),
        # The walkway outside 301, 303 and 305 (401, 403, 405) from the
        # toilets to the lift hall.
        rect("corridor", 26.0, 11.3, 47.6, 12.9),
        rect("elevator", 22.6, 14.3, 25.5, 16.6),
        rect("stairs", 12.0, 14.3, 20.8, 16.0),
        rect("stairs", 44.0, east_stairs[0], 47.6, east_stairs[1]),
        *toilets(44.0, 47.0, *toilet_rows),
    ]
    north = [(xs[0], xs[1]), (xs[1], xs[2]), (xs[2], xs[3]), (xs[4], xs[5]), (xs[5], xs[6]), (xs[6], xs[7])]
    for (x1, x0), label in zip(north, rooms_n):
        spaces.append(room(x0, 0, x1, 4.6, *label))
    for (x1, x0), label in zip(north, rooms_s):
        spaces.append(room(x0, 6.6, x1, 11.3, *label))
    outline = [[3.0, 0], [44.0, 0], [44.0, 1.9], [47.6, 1.9], [47.6, 12.9], [26.0, 12.9],
               [26.0, 16.6], [12.0, 16.6], [12.0, 11.3], [3.0, 11.3]]
    return {"id": level, "outline": outline, "spaces": spaces}


def floor_3f():
    return upper(
        "3F",
        [("302", "吳汶涓副教授"), ("304", "夏至賢教授"), ("306", "黃于飛副教授"),
         ("308", "卓信宏教授"), ("310", "陳麒元教授"), ("312", "教師研究室")],
        [("301", "教師研究室"), ("303", "朱志明副教授"), ("305", "吳政瑋助理教授"),
         ("307", "曾國鈞助理教授"), ("309", "陳懷恩教授"), ("311", "陳立勝助理教授")],
        ((1.9, 4.0), (4.0, 6.3), (6.3, 8.3)),
        (8.8, 11.3),
        11.3,
    )


def floor_4f():
    return upper(
        "4F",
        [("402", "互動媒體實驗室"), ("404", "普及運算暨環境網路實驗室"), ("406", "網路安全實驗室"),
         ("408", "智慧化行動計算實驗室"), ("410", "蘇維宗助理教授"), ("412", "研究實驗室")],
        [("401", "新一代通訊智慧運算實驗室"), ("403", "智慧型系統實驗室"), ("405", "研究實驗室"),
         ("407", "先進安全計算實驗室"), ("409", "黃朝曦副教授"), ("411", "研究實驗室")],
        ((1.9, 4.0), (4.0, 6.1), (6.1, 7.8)),
        (8.5, 11.3),
        11.3,
    )


def main():
    building = {
        "id": "dianzi",
        "name": "電資二館",
        "unit": "m",
        "floors": [flipped(f()) for f in (floor_1f, floor_2f, floor_3f, floor_4f)],
    }
    for floor in building["floors"]:
        codes = [s["code"] for s in floor["spaces"] if "code" in s and s["code"] != "資205"]
        assert len(codes) == len(set(codes)), (floor["id"], codes)
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/dianzi.json", root / "mobile/assets/campus_map/dianzi.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
