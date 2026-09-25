#!/usr/bin/env python3
"""Builds a phone-style backup zip (data.json + images/) from the demo library
in test_data/, for exercising the web app's import and rendering.

Adds what the demo lacks so the smoke run covers it: a note with an image and a
folder thumbnail (stored under phone-absolute paths, as a real backup has), a
book cover, and a note filed in the Crypt (which must never reach a browser).

    python3 tool/make_fixture_zip.py out.zip
"""
import json
import pathlib
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PHONE_IMAGES = '/data/user/0/com.solo.braim/app_flutter/images'


def main(out: str) -> None:
    data = json.loads((ROOT / 'test_data' / 'braim_demo.json').read_text())
    images = {
        'fixture-photo.jpg': ROOT / 'assets' / 'BACK03.jpg',
        'fixture-thumb.jpg': ROOT / 'assets' / 'BACK07.jpg',
        'fixture-cover.jpg': ROOT / 'assets' / 'BACK10.jpg',
    }

    first = data['notes'][0]
    first['blocks'].append({
        'id': 'fixture-image-block',
        'type': 'image',
        'text': '',
        'imagePath': f'{PHONE_IMAGES}/fixture-photo.jpg',
    })
    data['spaces'][0]['thumbnailPath'] = f'{PHONE_IMAGES}/fixture-thumb.jpg'
    data['books'][0]['coverPath'] = f'{PHONE_IMAGES}/fixture-cover.jpg'

    crypt_note = json.loads(json.dumps(data['notes'][2]))
    crypt_note['id'] = 'fixture-crypt-note'
    crypt_note['title'] = 'Crypt secret (must not reach the browser)'
    crypt_note['spaceId'] = '__crypt__'
    for b in crypt_note['blocks']:
        b['id'] = 'fixture-crypt-' + b['id']
    data['notes'].append(crypt_note)
    data['tutorialSeen'] = True

    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('data.json', json.dumps(data))
        for name, src in images.items():
            z.write(src, f'images/{name}')


if __name__ == '__main__':
    main(sys.argv[1])
