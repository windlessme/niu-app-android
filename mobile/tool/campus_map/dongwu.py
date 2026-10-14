#!/usr/bin/env python3
"""Generates app-content/campus-map/dongwu.json (實驗動物中心).

From the department's two plans (1F layout and 2F circulation plan), scaled
to the building's 21 m length in OpenStreetMap. North is up on both: the
tree line along the campus edge runs across the top of the 1F plan, and
the entrance faces south. The storage containers south of the building
are left out.
"""
import json
from pathlib import Path

W = 21.0


class Plan:
    """One plan: the building's box in pixels, left, top, right, bottom."""

    def __init__(self, left, top, right, bottom, depth):
        self.l, self.t, self.r, self.b, self.d = left, top, right, bottom, depth

    def rect(self, kind, px0, py0, px1, py1, name=None):
        sx, sy = W / (self.r - self.l), self.d / (self.b - self.t)
        x0, y0 = (px0 - self.l) * sx, (py0 - self.t) * sy
        space = {"kind": kind, "rect": [round(x0, 2), round(y0, 2), round((px1 - px0) * sx, 2),
                                        round((py1 - py0) * sy, 2)]}
        if name:
            space["name"] = name
        return space

    def room(self, *box, name):
        return self.rect("room", *box, name=name)


D = 8.6  # depth, from the 1F plan's proportions


def floor_1f():
    p = Plan(245, 320, 1005, 630, D)
    spaces = [
        p.rect("corridor", 372, 325, 730, 385),
        p.rect("corridor", 730, 325, 918, 630),
        p.room(248, 330, 372, 385, name="準備室"),
        p.room(248, 385, 372, 620, name="飼養區"),
        *[x for a, b in ((372, 492), (492, 610), (610, 730))
          for x in (p.room(a, 385, b, 460, name="準備室"), p.room(a, 460, b, 620, name="飼養區"))],
        p.rect("stairs", 840, 410, 915, 490),
        p.rect("stairs", 918, 395, 1000, 520),
        p.rect("elevator", 790, 520, 880, 600),
        p.rect("restroom", 918, 330, 1000, 390, name="廁所"),
        p.room(885, 525, 1000, 620, name="電氣室"),
    ]
    return {"id": "1F", "outline": [[0, 0], [W, 0], [W, D], [0, D]], "spaces": spaces}


def floor_2f():
    p = Plan(150, 315, 1222, 885, D)
    spaces = [
        p.rect("corridor", 325, 540, 705, 720),
        p.rect("corridor", 155, 620, 325, 720),
        p.rect("corridor", 840, 320, 1095, 885),
        p.room(155, 320, 325, 620, name="小鼠房（open cage）"),
        p.room(325, 320, 490, 540, name="大鼠房（一）"),
        p.room(490, 320, 655, 540, name="大鼠房（二）"),
        p.room(655, 320, 840, 500, name="行為房"),
        p.room(705, 500, 840, 645, name="檢疫房"),
        p.room(705, 645, 840, 720, name="緩衝區"),
        p.room(155, 720, 325, 885, name="小鼠房（challenge）"),
        p.room(325, 720, 600, 885, name="IVC 小鼠房"),
        p.room(600, 720, 840, 885, name="清洗室"),
        p.rect("stairs", 920, 390, 1095, 640),
        p.rect("elevator", 920, 690, 1040, 800),
        p.room(1095, 320, 1222, 585, name="兔房"),
        p.room(1095, 585, 1222, 690, name="墊飼料儲存室"),
        p.room(1050, 690, 1222, 885, name="行為房"),
    ]
    return {"id": "2F", "outline": [[0, 0], [W, 0], [W, D], [0, D]], "spaces": spaces}


def main():
    building = {"id": "dongwu", "name": "實驗動物中心", "unit": "m", "floors": [floor_1f(), floor_2f()]}
    text = json.dumps(building, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    # app-content is the copy iOS and others read; the app bundles its own.
    for out in (root / "app-content/campus-map/dongwu.json", root / "mobile/assets/campus_map/dongwu.json"):
        out.write_text(text, encoding="utf-8")
        print(out)


if __name__ == "__main__":
    main()
