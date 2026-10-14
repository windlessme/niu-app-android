#!/usr/bin/env python3
"""Generates app-content/campus-map/campus.json, the campus overview map.

    python3 tool/campus_map/campus.py [OSM_JSON]

Without an argument it downloads the campus area from the OpenStreetMap API
(map data © OpenStreetMap contributors, ODbL; the app shows the credit).
Coordinates become metres east (x) and south (y) of the campus centre, so the
app draws them like the floor plans: north is up.
"""
import json
import math
import sys
import urllib.request
from pathlib import Path

# 國立宜蘭大學 (way 237330506) with room for the streets around it.
SOUTH, WEST, NORTH, EAST = 24.7425, 121.7405, 24.7500, 121.7510
CAMPUS_WAY = 237330506
LAT0, LON0 = (SOUTH + NORTH) / 2, (WEST + EAST) / 2
MX = 111_320 * math.cos(math.radians(LAT0))
MY = 110_574

# Buildings with floor plans, by OSM way id.
PLANS = {256119621: "jiaose"}


def project(lat, lon):
    return [round((lon - LON0) * MX, 1), round((LAT0 - lat) * MY, 1)]


LEFT, TOP = project(NORTH, WEST)
RIGHT, BOTTOM = project(SOUTH, EAST)


def clip(points):
    """Pieces of a polyline inside the map's rectangle (Liang–Barsky)."""
    pieces, current = [], []
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        t0, t1, dx, dy = 0.0, 1.0, x1 - x0, y1 - y0
        inside = True
        for p, q in ((-dx, x0 - LEFT), (dx, RIGHT - x0), (-dy, y0 - TOP), (dy, BOTTOM - y0)):
            if p == 0:
                if q < 0:
                    inside = False
                    break
            else:
                t = q / p
                if p < 0:
                    t0 = max(t0, t)
                else:
                    t1 = min(t1, t)
        if not inside or t0 > t1:
            if len(current) > 1:
                pieces.append(current)
            current = []
            continue
        a = [round(x0 + t0 * dx, 1), round(y0 + t0 * dy, 1)]
        b = [round(x0 + t1 * dx, 1), round(y0 + t1 * dy, 1)]
        if not current or current[-1] != a:
            if len(current) > 1:
                pieces.append(current)
            current = [a]
        current.append(b)
        if t1 < 1:
            pieces.append(current)
            current = []
    if len(current) > 1:
        pieces.append(current)
    return pieces


def within(points):
    return any(LEFT <= x <= RIGHT and TOP <= y <= BOTTOM for x, y in points)


def fetch():
    url = f"https://api.openstreetmap.org/api/0.6/map.json?bbox={WEST},{SOUTH},{EAST},{NORTH}"
    request = urllib.request.Request(url, headers={"User-Agent": "NIU-Life campus map (hi@niu-life.app)"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


def area_kind(tags):
    if tags.get("leisure") in ("pitch", "stadium", "track") or tags.get("sport"):
        return "sport"
    if tags.get("natural") == "water" or tags.get("waterway"):
        return "water"
    if tags.get("landuse") in ("grass", "farmland") or tags.get("leisure") in ("park", "common") \
            or tags.get("natural") in ("wood", "heath"):
        return "green"
    if tags.get("amenity") in ("parking", "motorcycle_parking"):
        return "parking"
    return None


def road_kind(tags):
    highway = tags.get("highway")
    if highway in ("primary", "secondary", "tertiary", "unclassified", "residential", "road"):
        return "street"
    if highway == "service":
        return "service"
    if highway in ("footway", "pedestrian", "steps", "path", "track"):
        return "path"
    return None


def place_kind(tags):
    return "toilets" if tags.get("amenity") == "toilets" else None


def inside(point, polygon):
    x, y = point
    hit = False
    for (x0, y0), (x1, y1) in zip(polygon, polygon[1:] + polygon[:1]):
        if (y0 > y) != (y1 > y) and x < x0 + (x1 - x0) * (y - y0) / (y1 - y0):
            hit = not hit
    return hit


def main():
    data = json.loads(Path(sys.argv[1]).read_text()) if len(sys.argv) > 1 else fetch()
    nodes = {e["id"]: e for e in data["elements"] if e["type"] == "node"}
    ways = [e for e in data["elements"] if e["type"] == "way"]

    def line(way):
        return [project(nodes[n]["lat"], nodes[n]["lon"]) for n in way["nodes"] if n in nodes]

    def centre(points):
        return [round(sum(p[0] for p in points) / len(points), 1), round(sum(p[1] for p in points) / len(points), 1)]

    out = {
        "attribution": "© OpenStreetMap 貢獻者",
        "bounds": [LEFT, TOP, RIGHT, BOTTOM],
        "boundary": [],
        "buildings": [],
        "areas": [],
        "roads": [],
        "places": [],
    }
    boundary = out["boundary"] = next(line(w) for w in ways if w["id"] == CAMPUS_WAY)[:-1]
    for way in ways:
        tags = way.get("tags", {})
        points = line(way)
        if len(points) < 2 or way["id"] == CAMPUS_WAY:
            continue
        closed = way["nodes"][0] == way["nodes"][-1]
        if "building" in tags and closed and within(points):
            # Inside the campus line, whatever the tag: 復興國中 next door is
            # tagged school too.
            building = {"id": way["id"], "polygon": points[:-1], "campus": inside(centre(points[:-1]), boundary)}
            if tags.get("name"):
                building["name"] = tags["name"]
            if tags.get("building:levels", "").isdigit():
                building["levels"] = int(tags["building:levels"])
            if way["id"] in PLANS:
                building["plan"] = PLANS[way["id"]]
            out["buildings"].append(building)
        elif closed and area_kind(tags) and within(points):
            out["areas"].append({"kind": area_kind(tags), "polygon": points[:-1]})
        elif road_kind(tags):
            for piece in clip(points):
                road = {"kind": road_kind(tags), "line": piece}
                if tags.get("name"):
                    road["name"] = tags["name"]
                out["roads"].append(road)
        if closed and place_kind(tags) and inside(centre(points[:-1]), boundary):
            place = {"kind": place_kind(tags), "at": centre(points[:-1])}
            if tags.get("name"):
                place["name"] = tags["name"]
            out["places"].append(place)
    for node in nodes.values():
        tags = node.get("tags", {})
        kind = place_kind(tags)
        at = project(node["lat"], node["lon"]) if kind else None
        if kind and inside(at, boundary):
            place = {"kind": kind, "at": at}
            if tags.get("name"):
                place["name"] = tags["name"]
            out["places"].append(place)
    # Sports areas under buildings first; larger areas under smaller ones.
    out["areas"].sort(key=lambda a: -abs(sum(
        x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(a["polygon"], a["polygon"][1:] + a["polygon"][:1]))))
    out["buildings"].sort(key=lambda b: b["id"])
    out["places"].sort(key=lambda p: (p["kind"], p["at"]))
    text = json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n"
    root = Path(__file__).resolve().parents[3]
    for path in (root / "app-content/campus-map/campus.json", root / "mobile/assets/campus_map/campus.json"):
        path.write_text(text, encoding="utf-8")
        print(path, len(text))


if __name__ == "__main__":
    main()
