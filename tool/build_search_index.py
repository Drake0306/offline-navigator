#!/usr/bin/env python3
"""Build assets/search/ghatshila.sqlite from RAW OpenStreetMap (Overpass API)
within the Ghatshila bbox. Output: a `features` table with a normalized,
indexed `search` column queried by the app with LIKE (no FTS5).

Usage: python3 tool/build_search_index.py <overpass.json> <output.sqlite>
The <overpass.json> is produced by tool/generate_search_index.sh.
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
    s = s.lower()
    s = re.sub(r'\s+', ' ', s).strip()
    return s

def coords(el):
    # Nodes carry lat/lon directly; ways/relations carry a 'center' (out center).
    if 'lat' in el and 'lon' in el:
        return el['lat'], el['lon']
    c = el.get('center')
    if c:
        return c['lat'], c['lon']
    return None, None

def main():
    src, out = sys.argv[1], sys.argv[2]
    data = json.load(open(src, encoding='utf-8'))
    rows = []
    for el in data.get('elements', []):
        tags = el.get('tags') or {}
        name = tags.get('name')
        if not name:
            continue
        kind = classify(tags)
        if kind is None:
            continue
        lat, lon = coords(el)
        if lat is None or lon is None:
            continue
        name_en = tags.get('name:en', '')
        search = (normalize(name) + ' ' + normalize(name_en)).strip()
        rows.append((name, name_en, kind, float(lat), float(lon), search))
    # Dedupe on (normalized-search, kind, rounded coord).
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
    db.close()
    print(f'wrote {out}: {n} features')

if __name__ == '__main__':
    main()
