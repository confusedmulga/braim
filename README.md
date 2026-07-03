# Braim

A glassmorphic Google-Keep-style notes app built with Flutter. Local-only (no
account, no backend) - everything is stored on the device. (Project folder and
package id are still `keepy`/`com.keepy.keepy`; the user-facing app is **Braim**.)

## Features

- **Floating island nav** - a frosted pill at the bottom with **Home / Cards /
  Cortex**. The active tab expands with a label.
- **Compact search** - a deliberately narrow search bar on Home, Cards and
  Cortex filters notes, cards and folders live.
- **Home** - a masonry feed of notes. A note can interleave **multiple images
  between text**, and text supports **rich formatting**: Heading / Sub-heading /
  Body sizes, **bold**, *italic*, underline and highlight, via a shared toolbar
  that targets the focused line. The first image becomes the feed **thumbnail**,
  with the note's **folder name overlaid in black or white** (auto-contrast).
- **Cards** - save tweets/links. **Share a tweet to Braim** (Android share
  sheet) or paste a URL with the **+** button; it becomes a card with a
  best-effort preview, the **author's profile picture** in a small circle next
  to their name/handle, and a compact media image. Tweets use Twitter/X oEmbed
  (no API key) + unavatar for the avatar; other links use Open Graph tags.
  **Tapping a card opens it as a note**, the fetched preview and the source
  link (with a **Copy** button) are pinned at the top, with an editable note
  body (rich text + images) below. The card stays in Cards, plus in its Cortex
  folder if assigned.
- **Cortex** - folders for **both notes and cards**, shown as **square,
  round-cornered tiles** with an **uploadable thumbnail** and auto-contrast
  label. **Long-press** any note or card → *Move to cortex*. A folder's detail
  lists its notes (masonry) and its cards.
- **Glass everywhere** - translucent, blurred surfaces. The side pane and the
  Settings screen blur the live screen behind them. The background blur layer
  for Home/Cards/Cortex can be toggled in **Settings → Background blur**.

## Running

```bash
flutter pub get
flutter run            # with an Android emulator/device connected
# or build an installable debug APK:
flutter build apk --debug
```

Tested on Flutter 3.41 / Dart 3.11 against an Android emulator.

## Architecture

```
lib/
  models/        Note, NoteBlock (text|image), Space, TweetCard  (+ JSON)
  services/      storage (JSON file + images dir), image_picker wrapper,
                 link preview (oEmbed/OG), contrast (black/white label)
  state/         AppState (ChangeNotifier) — CRUD + persistence
  theme/         palette + ThemeData
  widgets/       glass panel, island nav, side pane, note/space/tweet cards,
                 thumbnail-with-auto-contrast-label
  screens/       root shell, home, cards, cortex (spaces), space detail,
                 note editor, card detail,
                 settings
```

- **State:** `provider` + a single `AppState` `ChangeNotifier`.
- **Persistence:** metadata in `keepy_data.json` in the app documents dir;
  picked images are copied into an `images/` subfolder (paths are stored).
- **Label contrast:** `palette_generator` finds the dominant color of a
  thumbnail; luminance > 0.5 → black text, else white (cached per image).

## Setting the background image

The background currently uses procedural aurora "orbs". To use a real photo:

1. Put the image at `assets/background.jpg`.
2. Declare it in `pubspec.yaml` under `flutter:` → `assets:`.
3. In `lib/widgets/glass.dart`, set
   `const String? kBackgroundAsset = 'assets/background.jpg';`.

The blur layer (Settings → Background blur) then frosts that photo on
Home/Cards/Cortex; turning it off shows the photo sharp.

## Platform notes / caveats

- **Tweet previews are best-effort.** X heavily restricts scraping, so an image
  isn't always available; the card always keeps the link and any text it could
  fetch. Tapping a card re-attempts the fetch.
- **Share-to-app is wired for Android** (intent filters in
  `AndroidManifest.xml`). iOS additionally needs a Share Extension target added
  in Xcode — not included in this prototype.
- `receive_sharing_intent` is pinned to **1.8.1**: 1.9.0 requires the
  preview Android SDK 37 and has a Gradle/Kotlin packaging issue. The pin is the
  reason for `kotlin.jvm.target.validation.mode=warning` in
  `android/gradle.properties`.
- `palette_generator` is marked discontinued upstream but still functions; swap
  for a manual luminance sampler later if needed.
