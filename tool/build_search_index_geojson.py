#!/usr/bin/env python3
"""Build a region search SQLite from an osmium GeoJSONSeq export of *named* OSM
features. Same schema + classify/normalize rules as build_search_index.py, but
reads line-delimited GeoJSON (so it scales to a whole district) instead of an
Overpass JSON blob.

Usage: python3 tool/build_search_index_geojson.py <named.geojsonseq> <out.sqlite>
The input is produced by `osmium export ... -f geojsonseq`.
"""
import sys, json, sqlite3, unicodedata, re


def classify(tags):
    if 'place' in tags:
        return 'place'
    if 'highway' in tags and tags.get('highway') not in ('footway', 'path', 'steps'):
        return 'road'
    if tags.get('natural') == 'water' or 'water' in tags or tags.get('waterway'):
        return 'water'
    for k in ('amenity', 'shop', 'tourism', 'leisure', 'office', 'healthcare',
              'aeroway', 'railway', 'public_transport'):
        if k in tags:
            return 'poi'
    return None


def normalize(s):
    if not s:
        return ''
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(c for c in s if not unicodedata.combining(c))
    return re.sub(r'\s+', ' ', s.lower()).strip()


def centroid(geom):
    """A representative (lat, lon) for any geometry: the point itself, or the
    average of all coordinates for lines/polygons (good enough for search)."""
    if not geom:
        return None, None
    if geom.get('type') == 'Point':
        c = geom.get('coordinates') or []
        return (c[1], c[0]) if len(c) >= 2 else (None, None)
    pts = []

    def collect(x):
        if x and isinstance(x[0], (int, float)):
            pts.append(x)
        else:
            for y in x:
                collect(y)

    try:
        collect(geom.get('coordinates') or [])
    except Exception:
        return None, None
    if not pts:
        return None, None
    return (sum(p[1] for p in pts) / len(pts), sum(p[0] for p in pts) / len(pts))


def main():
    src, out = sys.argv[1], sys.argv[2]
    rows = []
    with open(src, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line[0] == '\x1e':  # RFC 8142 record separator
                line = line[1:]
            try:
                feat = json.loads(line)
            except Exception:
                continue
            tags = feat.get('properties') or {}
            name = tags.get('name')
            if not name:
                continue
            kind = classify(tags)
            if kind is None:
                continue
            lat, lon = centroid(feat.get('geometry'))
            if lat is None or lon is None:
                continue
            name_en = tags.get('name:en', '')
            search = (normalize(name) + ' ' + normalize(name_en)).strip()
            rows.append((name, name_en, kind, float(lat), float(lon), search))

    seen, deduped = set(), []
    for r in rows:
        key = (r[5], r[2], round(r[3], 5), round(r[4], 5))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(r)

    db = sqlite3.connect(out)
    db.execute('DROP TABLE IF EXISTS features')
    db.execute('''CREATE TABLE features(
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, name_en TEXT,
        kind TEXT NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL,
        search TEXT NOT NULL)''')
    db.executemany(
        'INSERT INTO features(name,name_en,kind,lat,lon,search) VALUES (?,?,?,?,?,?)',
        deduped)
    db.execute('CREATE INDEX idx_features_search ON features(search)')
    db.commit()
    n = db.execute('SELECT count(*) FROM features').fetchone()[0]
    by = db.execute('SELECT kind, count(*) FROM features GROUP BY kind').fetchall()
    db.close()
    print(f'wrote {out}: {n} features')
    for k, c in by:
        print(f'  {k}: {c}')


if __name__ == '__main__':
    main()
