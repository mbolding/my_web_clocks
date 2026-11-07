#!/usr/bin/env python3
"""Builds the data for Map Browser's built-in layers, using only Python's standard
library; run it from anywhere:

    python3 desktop_widget/Maps/tools/build_layers.py

It only needs running when the data should change, and writes two Swift files:

Maps/AlabamaData.swift, Alabama's 67 county outlines and the long trails, from
- the Census Bureau's 2023 cartographic boundary counties at 1:500,000 (public domain),
  kept for Alabama, state code 01;
- the trails' OpenStreetMap route relations (ODbL), through the OpenStreetMap API, by
  the ids listed in TRAILS below, clipped to Alabama;
- for the Alabama Scenic River Trail and the planned Singing River Trail, which have no
  route in OpenStreetMap, the lines drawn on the "67 Counties" wall map, turned back from
  that map's Albers projection (fitted to its state parks, to about 50 m).

Maps/CorpsData.swift, every Army Corps of Engineers campground in the country with its
site count and Recreation.gov id, from Recreation.gov's RIDB export (public domain; a
250 MB download). RIDB files reservable day-use picnic shelters as campgrounds too, so a
place is kept only if it has a site for staying the night.

Lines are thinned with Douglas-Peucker to SIMPLIFY_M metres and stored as Google
encoded polylines, five decimal places, which Map Browser decodes at launch. Downloads
are kept in .cache/ beside this script, which git ignores.
"""

import io
import json
import math
import re
import sys
import time
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "AlabamaData.swift"
CORPS_OUT = HERE.parent / "CorpsData.swift"
CACHE = HERE / ".cache"  # downloads, gitignored
USER_AGENT = "MapBrowser/1.0 (macOS; +https://github.com/mbolding/my_web_clocks)"

COUNTIES_URL = "https://www2.census.gov/geo/tiger/GENZ2023/kml/cb_2023_us_county_500k.zip"
RIDB_URL = "https://ridb.recreation.gov/downloads/RIDBFullExport_V1_CSV.zip"
RIDB_CORPS = "130"  # the Corps' OrgID in RIDB
# Campsite types for staying the night; the rest are picnic shelters, day use and staff.
OVERNIGHT = re.compile(r"^(STANDARD|TENT|RV|WALK TO|HIKE TO|BOAT IN|EQUESTRIAN|GROUP STANDARD|GROUP TENT|OVERNIGHT SHELTER|CABIN|YURT|LEAN-TO)")
SIMPLIFY_M = 25

# The long trails, as the wall map shows them: name, kind, and an OpenStreetMap route
# relation, clipped to Alabama. Kinds match the wall map's: hike dashed, bike solid,
# water for paddling, plan dotted.
TRAILS = [
    ("Pinhoti Trail", "hike", 1642836),
    ("Chief Ladiga Trail", "bike", 326630),
    ("Natchez Trace Parkway", "bike", 3300030),
    ("Singing River Trail (Richard Martin section)", "bike", 12485285),
]

# Two that OpenStreetMap has no route for, traced from the wall map instead. WALL_MAP
# copies those two drawings from the artifact, in its 600 x 945 frame.
TRACED = [
    ("Alabama Scenic River Trail", "water"),
    ("Singing River Trail, planned", "plan"),
]
WALL_MAP = HERE / "wall_map.json"

# The wall map's projection: Albers equal-area on a sphere, standard parallels 30.5 and
# 34.8 N, origin 30 N 86.8 W, then an affine fit to its frame from its 24 state parks,
# whose positions it gives both ways (rms 0.04 px).
ALBERS = dict(lat1=30.5, lat2=34.8, lat0=30.0, lon0=-86.8)
FRAME = dict(ax=11168.014, bx=0.1443, cx=282.5368, ay=0.0194, by=-11163.2939, cy=983.5074)
OSM_API = "https://api.openstreetmap.org/api/0.6"


def fetch(url, name, data=None):
    CACHE.mkdir(exist_ok=True)
    path = CACHE / name
    if path.exists():
        return path.read_bytes()
    req = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=300) as r:
        body = r.read()
    path.write_bytes(body)
    return body


# ---------- geometry ----------

def metres(a, b, lat0):
    """Equirectangular offset in metres, plenty for thinning at county scale."""
    k = 111_320.0
    return ((b[0] - a[0]) * k * math.cos(math.radians(lat0)), (b[1] - a[1]) * k)


def simplify(points, tol=SIMPLIFY_M):
    """Douglas-Peucker on (lon, lat) points, tolerance in metres."""
    if len(points) < 3:
        return points
    lat0 = sum(p[1] for p in points) / len(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        dx, dy = metres(points[i], points[j], lat0)
        seg = math.hypot(dx, dy)
        best, at = 0.0, None
        for k in range(i + 1, j):
            px, py = metres(points[i], points[k], lat0)
            d = abs(px * dy - py * dx) / seg if seg else math.hypot(px, py)
            if d > best:
                best, at = d, k
        if at is not None and best > tol:
            keep[at] = True
            stack += [(i, at), (at, j)]
    return [p for p, k in zip(points, keep) if k]


def encode(points):
    """Google's encoded polyline format, latitude first, 1e-5 degrees."""
    out, last = [], (0, 0)
    for lon, lat in points:
        cur = (round(lat * 1e5), round(lon * 1e5))
        for v in (cur[0] - last[0], cur[1] - last[1]):
            v = ~(v << 1) if v < 0 else v << 1
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        last = cur
    return "".join(out)


# ---------- counties ----------

def counties():
    raw = fetch(COUNTIES_URL, "cb_2023_us_county_500k.zip")
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        kml = z.read(next(n for n in z.namelist() if n.endswith(".kml"))).decode("utf-8")
    result = []
    for block in kml.split("<Placemark")[1:]:
        field = lambda k: re.search(rf'<SimpleData name="{k}">([^<]*)<', block).group(1)
        if field("STATEFP") != "01":
            continue
        rings = []
        # Outer boundaries only: Alabama's counties have no holes worth drawing.
        for outer in re.findall(r"<outerBoundaryIs>.*?<coordinates>(.*?)</coordinates>", block, re.S):
            pts = [tuple(map(float, c.split(",")[:2])) for c in outer.split()]
            rings.append(simplify(pts))
        name = field("NAME")
        result.append((slug(name), name, rings))
    result.sort()
    assert len(result) == 67, len(result)
    return result


def slug(name):
    return re.sub(r"[^a-z]+", "-", name.lower().replace(".", "")).strip("-")


def inside(pt, rings):
    """Even-odd point in polygon, over rings with a bounding box each."""
    x, y = pt
    for (x0, y0, x1, y1), ring in rings:
        if not (x0 <= x <= x1 and y0 <= y <= y1):
            continue
        hit = False
        for (ax, ay), (bx, by) in zip(ring, ring[1:] + ring[:1]):
            if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
                hit = not hit
        if hit:
            return True
    return False


# ---------- trails ----------

def route(rid):
    """A route relation's ways as (lon, lat) lines, joined end to end where they meet."""
    body = json.loads(fetch(f"{OSM_API}/relation/{rid}/full.json", f"relation-{rid}.json"))
    nodes = {e["id"]: (e["lon"], e["lat"]) for e in body["elements"] if e["type"] == "node"}
    ways = {e["id"]: e["nodes"] for e in body["elements"] if e["type"] == "way"}
    rel = next(e for e in body["elements"] if e["type"] == "relation" and e["id"] == rid)
    lines = [[nodes[n] for n in ways[m["ref"]] if n in nodes]
             for m in rel["members"] if m["type"] == "way" and m["ref"] in ways]
    return join([l for l in lines if len(l) > 1])


def join(lines):
    """Greedily chains lines that share an end, so a trail is a few long lines."""
    lines = [list(l) for l in lines]
    out = []
    while lines:
        cur = lines.pop(0)
        grown = True
        while grown:
            grown = False
            for i, l in enumerate(lines):
                if l[0] == cur[-1]: cur += l[1:]
                elif l[-1] == cur[-1]: cur += l[-2::-1]
                elif l[-1] == cur[0]: cur = l[:-1] + cur
                elif l[0] == cur[0]: cur = l[:0:-1] + cur
                else: continue
                lines.pop(i)
                grown = True
                break
        out.append(cur)
    return out


def clip(lines, rings):
    """Keeps the runs of each line that lie in Alabama."""
    out = []
    for line in lines:
        run = []
        for p in line:
            if inside(p, rings):
                run.append(p)
            else:
                if len(run) > 1: out.append(run)
                run = []
        if len(run) > 1: out.append(run)
    return out


def unproject(x, y):
    """A point on the wall map back to (lon, lat), inverting FRAME then ALBERS."""
    f, a = FRAME, ALBERS
    det = f["ax"] * f["by"] - f["bx"] * f["ay"]
    u = ((x - f["cx"]) * f["by"] - (y - f["cy"]) * f["bx"]) / det
    v = ((y - f["cy"]) * f["ax"] - (x - f["cx"]) * f["ay"]) / det
    r = math.radians
    n = (math.sin(r(a["lat1"])) + math.sin(r(a["lat2"]))) / 2
    c = math.cos(r(a["lat1"])) ** 2 + 2 * n * math.sin(r(a["lat1"]))
    rho0 = math.sqrt(c - 2 * n * math.sin(r(a["lat0"]))) / n
    rho = math.hypot(u, rho0 - v)
    theta = math.atan2(u, rho0 - v)
    lat = math.degrees(math.asin((c - (rho * n) ** 2) / (2 * n)))
    return (a["lon0"] + math.degrees(theta / n), lat)


def svg_lines(d):
    """The M/L/Z polylines of an SVG path, in the wall map's frame."""
    lines, cur = [], []
    for cmd, args in re.findall(r"([MLZ])([^MLZ]*)", d):
        nums = list(map(float, re.findall(r"-?\d+(?:\.\d+)?", args)))
        pts = list(zip(nums[0::2], nums[1::2]))
        if cmd == "M":
            if len(cur) > 1: lines.append(cur)
            cur = pts
        elif cmd == "L":
            cur += pts
        elif cmd == "Z" and cur:
            cur.append(cur[0])
    if len(cur) > 1: lines.append(cur)
    return lines


def trails(county_rings):
    rings = [((min(x for x, _ in r), min(y for _, y in r), max(x for x, _ in r), max(y for _, y in r)), r)
             for _, _, rs in county_rings for r in rs]
    result = []
    for name, kind, rid in TRAILS:
        lines = [simplify(l) for l in clip(route(rid), rings)]
        lines = [l for l in lines if len(l) > 1]
        print(f"  {name}: {len(lines)} lines, {sum(map(len, lines))} points")
        result.append((name, kind, lines))
        time.sleep(1)  # the OSM API asks for a gentle pace
    drawn = {t["name"]: t["d"] for t in json.loads(WALL_MAP.read_text())["trails"]}
    for name, kind in TRACED:
        lines = [[unproject(x, y) for x, y in l] for l in svg_lines(drawn[name])]
        print(f"  {name}: traced, {len(lines)} lines, {sum(map(len, lines))} points")
        result.append((name, kind, lines))
    return result


# ---------- output ----------

def swift_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write(counties, trails):
    lines = [
        "// AlabamaData — generated by tools/build_layers.py; don't edit by hand.",
        "// Counties: U.S. Census Bureau, 2023 cartographic boundaries, 1:500,000.",
        "// Trails: © OpenStreetMap contributors, ODbL, except the Alabama Scenic River Trail",
        "// and the planned Singing River route, traced from the 67 Counties wall map. Each",
        "// line is a Google encoded polyline (1e-5 degrees).",
        "",
        "enum AlabamaData {",
        "    struct County { let id: String; let name: String; let rings: [String] }",
        "    struct Trail { let name: String; let kind: String; let lines: [String] }",
        "",
        "    static let counties: [County] = [",
    ]
    for cid, name, rings in counties:
        enc = ", ".join(swift_string(encode(r)) for r in rings)
        lines.append(f"        County(id: {swift_string(cid)}, name: {swift_string(name)}, rings: [{enc}]),")
    lines += ["    ]", "", "    static let trails: [Trail] = ["]
    for name, kind, parts in trails:
        enc = ", ".join(swift_string(encode(p)) for p in parts)
        lines.append(f"        Trail(name: {swift_string(name)}, kind: {swift_string(kind)}, lines: [{enc}]),")
    lines += ["    ]", "}", ""]
    OUT.write_text("\n".join(lines))
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


# ---------- Corps campgrounds ----------

def title(name):
    """RIDB's capitals, as words: "PRAIRIE CREEK (AL)" to "Prairie Creek (AL)"."""
    if name != name.upper():
        return name
    small = {"OF", "THE", "AT", "ON", "IN", "AND", "BY"}
    words = []
    for i, w in enumerate(name.split()):
        bare = w.strip("()")
        if len(bare) <= 2 and bare.isalpha() and bare not in small:
            words.append(w)                      # AL, CG, R
        elif bare in small and i:
            words.append(w.lower())
        else:
            words.append(w.capitalize() if w[0] != "(" else "(" + w[1:].capitalize())
    return " ".join(words)


def corps():
    import csv
    csv.field_size_limit(sys.maxsize)
    path = CACHE / "RIDBFullExport_V1_CSV.zip"
    if not path.exists():
        fetch(RIDB_URL, path.name)
    z = zipfile.ZipFile(path)

    def rows(name):
        with z.open(name) as f:
            yield from csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))

    ids = {r["EntityID"] for r in rows("OrgEntities_API_v1.csv")
           if r["OrgID"] == RIDB_CORPS and r["EntityType"] == "Campground"}
    sites = {}
    for r in rows("Campsites_API_v1.csv"):
        if r["FacilityID"] in ids and OVERNIGHT.match(r["CampsiteType"]):
            sites[r["FacilityID"]] = sites.get(r["FacilityID"], 0) + 1
    out = []
    for r in rows("Facilities_API_v1.csv"):
        fid = r["FacilityID"]
        if fid not in ids or r["Enabled"] != "true":
            continue
        lat, lon = float(r["FacilityLatitude"] or 0), float(r["FacilityLongitude"] or 0)
        if not lat or not lon:
            continue
        # No campsites listed, but named as a campground: keep it, with no count.
        if fid not in sites and "CAMP" not in r["FacilityName"].upper():
            continue
        out.append((fid, title(r["FacilityName"].strip()), lat, lon, sites.get(fid, 0)))
    out.sort(key=lambda c: c[1])
    return out


def write_corps(camps):
    lines = [
        "// CorpsData — generated by tools/build_layers.py; don't edit by hand.",
        "// U.S. Army Corps of Engineers campgrounds, from Recreation.gov's RIDB (public domain).",
        "// sites counts the sites for staying the night; 0 where RIDB lists none.",
        "",
        "enum CorpsData {",
        "    struct Campground { let id: String; let name: String; let lat: Double; let lon: Double; let sites: Int }",
        "",
        "    static let campgrounds: [Campground] = [",
    ]
    for fid, name, lat, lon, n in camps:
        lines.append(f"        Campground(id: {swift_string(fid)}, name: {swift_string(name)}, "
                     f"lat: {lat:.5f}, lon: {lon:.5f}, sites: {n}),")
    lines += ["    ]", "}", ""]
    CORPS_OUT.write_text("\n".join(lines))
    print(f"wrote {CORPS_OUT} ({CORPS_OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    c = counties()
    print(f"{len(c)} counties, {sum(len(r) for _, _, rs in c for r in rs)} points")
    write(c, trails(c))
    camps = corps()
    print(f"{len(camps)} Corps campgrounds")
    write_corps(camps)
