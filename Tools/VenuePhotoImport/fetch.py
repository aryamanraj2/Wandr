#!/usr/bin/env python3
"""Pull candidate photographs for the Khan Market demo venues.

Landmarks come from Wikimedia Commons, which genuinely has the real place. Rooms — cafes,
bars, shops — are not on Commons, so those draw vibe-matched CC0/CC-BY imagery from
Openverse instead. Both are licence-clean to bundle, unlike Places photos.

Writes candidates to a staging folder for review. Nothing goes near the asset catalog
until a human has looked at it.
"""
import json, os, sys, urllib.parse, urllib.request

UA = {'User-Agent': 'WandrDemo/1.0 (demo asset sourcing)'}

# seed: (brand query, vibe fallback).
#
# The brand is tried first across both collections — for a chain, a photograph of any
# outlet carries the name and nobody reads the branch off a card. Only when the brand is
# in no open-licensed collection at all does the vibe query stand in. Landmarks almost
# always resolve on the brand pass, because there the brand *is* the place.
VENUES = {
    185: ('Khan Chacha Delhi kebab',            'seekh kebab grill indian street food'),
    186: ('Big Chill Cafe Delhi',               'colourful diner cafe interior cake counter'),
    187: ('Mamagoto restaurant',                'asian restaurant interior dim lighting'),
    188: ('Town Hall restaurant Khan Market',   'elegant european restaurant dining room'),
    189: ('Perch Wine Coffee Bar Delhi',        'wine bar interior bottles shelf'),
    190: ('Tres restaurant Delhi',              'modern bistro bar counter interior'),
    191: ('Amour Bistro Delhi',                 'rooftop terrace bar fairy lights evening'),
    192: ('Bahrisons Booksellers Khan Market',  'bookshop interior shelves books'),
    193: ('Full Circle Cafe Turtle Delhi',      'bookstore cafe reading table coffee'),
    194: ('Good Earth store India',             'home decor store interior textiles'),
    195: ('Lodhi Gardens Delhi',                'landscaped park tomb garden'),
    196: ('India Gate New Delhi',               'war memorial arch lawns'),
    197: ('National Gallery of Modern Art New Delhi', 'art gallery interior paintings'),
    360: ('Sunder Nursery Delhi',               'heritage garden pathway trees'),
    361: ('Khan Market Delhi',                  'market lane shopfronts evening'),
    362: ('Middle Lane listening bar Delhi',    'vinyl record listening bar turntable'),
    363: ('Khan Terrace beer garden Delhi',     'beer garden terrace tables evening'),
    364: ('Anand Stationers Khan Market',       'stationery shop pens notebooks display'),
    365: ('Khan Market cookery Delhi',          'cooking class kitchen counter'),
    366: ('Khan Market breakfast Delhi',        'breakfast counter coffee pastries morning'),
}

MIN_SIDE = 1200


def get(url, timeout=30):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout).read()


def wikimedia(query, limit=6):
    q = urllib.parse.quote(query)
    url = (f'https://commons.wikimedia.org/w/api.php?action=query&generator=search'
           f'&gsrsearch={q}&gsrnamespace=6&gsrlimit={limit}&prop=imageinfo'
           f'&iiprop=url|size|extmetadata&format=json')
    pages = (json.loads(get(url)).get('query', {}).get('pages') or {}).values()
    out = []
    for p in pages:
        ii = p['imageinfo'][0]
        if min(ii.get('width', 0), ii.get('height', 0)) < MIN_SIDE:
            continue
        meta = ii.get('extmetadata', {})
        out.append({
            'url': ii['url'],
            'w': ii['width'], 'h': ii['height'],
            'title': p['title'],
            'licence': meta.get('LicenseShortName', {}).get('value', '?'),
            'author': meta.get('Artist', {}).get('value', '?')[:80],
        })
    return out


def openverse(query, limit=8):
    q = urllib.parse.quote(query)
    url = (f'https://api.openverse.org/v1/images/?q={q}&size=large'
           f'&page_size={limit}&mature=false')
    out = []
    for r in json.loads(get(url)).get('results', []):
        if min(r.get('width') or 0, r.get('height') or 0) < MIN_SIDE:
            continue
        out.append({
            'url': r['url'], 'w': r['width'], 'h': r['height'],
            'title': (r.get('title') or '')[:60],
            'licence': r.get('license', '?'),
            'author': (r.get('creator') or '?')[:40],
        })
    return out


def main():
    stage = sys.argv[1] if len(sys.argv) > 1 else 'venue-candidates'
    os.makedirs(stage, exist_ok=True)
    manifest = {}

    for seed, (brand, vibe) in sorted(VENUES.items()):
        hits, used, stage_name = [], None, None
        # Brand first, across both collections; vibe only if the brand is nowhere.
        for label, query, fn in (('brand', brand, wikimedia), ('brand', brand, openverse),
                                 ('vibe',  vibe,  openverse)):
            try:
                hits = fn(query)
            except Exception as e:
                print(f'  {seed}: {fn.__name__} failed — {e}')
                hits = []
            if hits:
                used, stage_name = query, label
                break
        if not hits:
            print(f'  {seed}: nothing >= {MIN_SIDE}px for either query')
            continue

        saved = []
        for i, h in enumerate(hits[:3]):
            path = os.path.join(stage, f'venue-{seed}__{i}.jpg')
            try:
                data = get(h['url'], timeout=60)
                with open(path, 'wb') as f:
                    f.write(data)
                saved.append({**h, 'file': os.path.basename(path)})
            except Exception as e:
                print(f'  {seed}[{i}]: download failed — {e}')
        if saved:
            manifest[seed] = {'query': used, 'match': stage_name, 'candidates': saved}
            print(f'  {seed}: {len(saved)} via {stage_name:<5} "{used[:34]}"  [{saved[0]["w"]}x{saved[0]["h"]} {saved[0]["licence"]}]')

    with open(os.path.join(stage, 'manifest.json'), 'w') as f:
        json.dump(manifest, f, indent=2)
    print(f'\nstaged {len(manifest)} venues -> {stage}/')


if __name__ == '__main__':
    main()
