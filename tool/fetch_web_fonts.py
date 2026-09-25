#!/usr/bin/env python3
"""Downloads the fallback fonts Flutter's web engine would otherwise fetch from
fonts.gstatic.com at runtime (Roboto, emoji, symbols, Indic scripts…) into
web/fonts/gstatic/, mirroring gstatic's paths. web/flutter_bootstrap.js points
the engine's `fontFallbackBaseUrl` there, so text never renders as boxes when
the computer has no internet (the phone's hotspot, say).

The list comes from the installed Flutter SDK's own font manifest, so it always
matches the engine that builds the app. CJK families (hundreds of files, ~60 MB)
are skipped; see the README.

    python3 tool/fetch_web_fonts.py            # uses `flutter` on PATH
    python3 tool/fetch_web_fonts.py --all      # include CJK (~60 MB more)
    python3 tool/fetch_web_fonts.py --list     # show what would be fetched
"""
import os
import pathlib
import re
import shutil
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'web' / 'fonts' / 'gstatic'
BASE = 'https://fonts.gstatic.com/s/'
SKIP = re.compile(r'^Noto Sans (JP|KR|HK|TC|SC)\b')


def flutter_root() -> pathlib.Path:
    exe = shutil.which('flutter')
    if exe is None:
        sys.exit('flutter not found on PATH')
    return pathlib.Path(os.path.realpath(exe)).parent.parent


def manifest() -> list[tuple[str, str]]:
    engine = flutter_root() / 'bin' / 'cache' / 'flutter_web_sdk' / 'lib' / '_engine' / 'engine'
    data = (engine / 'font_fallback_data.dart').read_text()
    fonts = re.findall(r"NotoFont\(\s*'([^']+)',\s*'([^']+)'", data)
    roboto = re.search(r"fontFallbackBaseUrl\}(roboto/[^']+\.woff2)",
                       (engine / 'canvaskit' / 'fonts.dart').read_text())
    skip_cjk = '--all' not in sys.argv
    out = [(name, path) for name, path in fonts
           if not (skip_cjk and SKIP.match(name))]
    if roboto:
        out.insert(0, ('Roboto', roboto.group(1)))
    return out


def main() -> None:
    fonts = manifest()
    if '--list' in sys.argv:
        for name, path in fonts:
            print(f'{name}\t{path}')
        return
    total = 0
    for name, path in fonts:
        dest = OUT / path
        if not dest.exists():
            dest.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(BASE + path, timeout=60) as r:
                tmp = dest.with_suffix('.part')
                tmp.write_bytes(r.read())
                tmp.rename(dest)
        total += dest.stat().st_size
    print(f'{len(fonts)} fonts, {total / 1e6:.1f} MB in {OUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
