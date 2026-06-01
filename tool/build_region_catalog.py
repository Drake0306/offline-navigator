#!/usr/bin/env python3
"""Assemble regions.json (the app's region catalog) from generated region files
+ a metadata descriptor. Computes each file's size + sha256 so the on-device
downloader can verify integrity.

Usage:
  python3 tool/build_region_catalog.py <out_dir> <base_url> <meta.json> <catalog.json>

<out_dir>   build/regiongen/out  (holds <id>/<id>.{pmtiles,valhalla.tar,admins.sqlite,search.sqlite})
<base_url>  e.g. https://github.com/<owner>/<repo>/releases/download/<tag>
<meta.json> [{"id","name","state","bbox":[minLon,minLat,maxLon,maxLat],"version"}]
"""
import sys, json, hashlib, os

# region file key -> generated filename suffix (also the release asset name)
FILEMAP = {
    'tiles': '.pmtiles',
    'valhalla': '.valhalla.tar',
    'admins': '.admins.sqlite',
    'search': '.search.sqlite',
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    out_dir, base_url, meta_path, catalog_path = sys.argv[1:5]
    meta = json.load(open(meta_path))
    regions = []
    for m in meta:
        rid = m['id']
        files = {}
        for key, suffix in FILEMAP.items():
            fname = rid + suffix
            fpath = os.path.join(out_dir, rid, fname)
            files[key] = {
                'url': f'{base_url}/{fname}',
                'bytes': os.path.getsize(fpath),
                'sha256': sha256(fpath),
            }
        regions.append({
            'id': rid,
            'name': m['name'],
            'state': m['state'],
            'bbox': m['bbox'],
            'version': m.get('version', 1),
            'files': files,
        })
    json.dump({'schemaVersion': 1, 'regions': regions},
              open(catalog_path, 'w'), indent=2)
    print(f'wrote {catalog_path} with {len(regions)} region(s)')


if __name__ == '__main__':
    main()
