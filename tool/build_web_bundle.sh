#!/usr/bin/env bash
# Builds the web app and places it inside the Android app, so the phone can
# serve it to a browser ("Open on computer", remote mode). Run it before
# `flutter build apk` / `flutter build appbundle`; the APK works without it,
# but then "Open on computer" serves a page saying the web app is missing.
#
#   tool/build_web_bundle.sh            # then: flutter build appbundle
#
# What goes in (android/app/src/main/assets/web/, git-ignored):
#   - the dart2js build and the CanvasKit engine browsers load (the skwasm /
#     wasm variants and debug symbols are left out);
#   - the fallback fonts most text needs (Roboto, emoji, symbols, math, Latin/
#     Greek/Cyrillic, Arabic and Indic scripts); rarer scripts are fetched from
#     Google when the computer is online.
# Left out: the app's own Flutter assets (wallpapers, fonts under
# assets/assets/) — the phone serves those from its own asset bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=android/app/src/main/assets/web
BUILD=build/web_bundle

python3 tool/fetch_web_fonts.py
flutter build web --release --no-web-resources-cdn --pwa-strategy=none \
  --base-href / -o "$BUILD"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$BUILD"/. "$OUT"/

# Served from the phone's rootBundle instead of a second copy.
rm -rf "$OUT/assets/assets"
# Only the CanvasKit builds a dart2js app loads.
rm -rf "$OUT"/canvaskit/skwasm* "$OUT"/canvaskit/wimp* "$OUT"/canvaskit/*.symbols \
       "$OUT"/canvaskit/chromium/*.symbols
rm -f "$OUT/flutter_service_worker.js" "$OUT"/*.map
# Core fallback fonts only.
keep='^(roboto|notocoloremoji|notosans|notosanssymbols|notosanssymbols2|notosansmath|notosansarabic|notosansdevanagari|notosansbengali|notosansgujarati|notosansgurmukhi|notosanstamil|notosanstelugu|notosanskannada|notosansmalayalam|notosansoriya)$'
for d in "$OUT"/fonts/gstatic/*/; do
  name=$(basename "$d")
  [[ "$name" =~ $keep ]] || rm -rf "$d"
done

echo "Web bundle: $(du -sh "$OUT" | cut -f1) in $OUT"
