# Braim

A Google Keep style notes app built with Flutter. It is local only, with no
account and no backend, so everything is stored on the device.

The Flutter package name is still `keepy` and the data file is `keepy_data.json`
for backward compatibility. The Android application id and namespace are
`com.solo.braim`, and the user facing app is Braim.

## Features

- Bottom navigation with three tabs: Home, Cards, and Cortex. The active tab
  expands to show its label. Tapping the active tab, or its title at the top,
  scrolls the feed back to the top.
- Search and sort. A search bar on Home, Cards, and Cortex filters notes, cards,
  and folders live. A sort control next to it orders the feed by recently added
  (default), oldest first, alphabetical A to Z, or alphabetical Z to A.
- Home. A masonry feed of notes. A note can place multiple images between blocks
  of text, and text supports rich formatting: Heading, Sub-heading, and Body
  sizes, plus bold, italic, underline, and highlight from a toolbar that targets
  the focused line. Notes also support checklists with tappable checkboxes and an
  optional colour tag. The first image becomes the feed thumbnail, with the
  note's folder name overlaid in black or white based on contrast.
- Cards. Save tweets and links. Share a tweet to Braim from the Android share
  sheet, or paste a URL with the plus button, and it becomes a card with a best
  effort preview. Tweets use Twitter/X oEmbed with no API key, plus unavatar for
  the author avatar. Other links use Open Graph tags. Tapping a card opens it
  like a note: the fetched preview and the source link, with a copy button, stay
  pinned at the top, and an editable note body sits below. The card stays in
  Cards, and also in its Cortex folder if one is assigned.
- Cortex. Folders that hold both notes and cards, shown as square, round
  cornered tiles with an uploadable thumbnail and a contrast matched label. A
  folder that has a cover photo opens with a collapsing header that tucks into
  the top bar as you scroll; a folder without one shows a plain titled bar. Long
  press any note or card to move it into a folder.
- Crypt. A special folder that only opens with a fingerprint or the device
  screen lock. Its contents never appear in feeds or search. Note that Crypt
  locks access only; items are stored unencrypted on the device and are included
  readable in backups, so it is not meant for passwords or bank details.
- Archive and Recently deleted. Archiving hides an item without deleting it.
  Deleted items wait 30 days in Recently deleted before they are removed for
  good, and can be restored in the meantime.
- Appearance. Choose System, Light, or Dark in Settings. System follows the
  device theme.
- Backup and restore. Export a single zip containing data and images, and share
  it to Drive, Files, or anywhere. Restore replaces the current contents from a
  chosen zip. A reminder banner appears on Home when the data has not been backed
  up recently.
- Space Grotesk (SIL Open Font License) is bundled and used throughout.
- English localization scaffold under `lib/l10n`.

## Running

```bash
flutter pub get
flutter run            # with an Android emulator or device connected
# or build an installable debug APK:
flutter build apk --debug
```

Tested on Flutter 3.41 and Dart 3.11 against an Android emulator.

## Architecture

```
lib/
  l10n/          localized strings (app_en.arb) and generated bindings
  models/        Note, NoteBlock (text or image), Space, TweetCard, with JSON
  services/      storage (JSON file plus images dir), image picker wrapper,
                 link preview (oEmbed and Open Graph), contrast helper, backup
  state/         AppState (ChangeNotifier): CRUD, sorting, and persistence
  theme/         palette, note colours, and ThemeData
  widgets/       navigation island, search field, sort button, note, space, and
                 card tiles, sheets, and the open/close morph
  screens/       root shell, home, cards, cortex (spaces), space detail,
                 note editor, card detail, archive, recently deleted, settings
```

- State is provided by `provider` with a single `AppState` `ChangeNotifier`.
- Persistence writes metadata to `keepy_data.json` in the app documents
  directory using an atomic temp, backup, rename sequence, with a `.bak`
  fallback on load. Picked images are copied into an `images/` subfolder and
  referenced by path. Writes are debounced and run off the main isolate.
- Label contrast uses `palette_generator` to find a thumbnail's dominant colour.
  A luminance above 0.5 gives black text, otherwise white, cached per image.

## Platform notes and caveats

- Tweet previews are best effort. X restricts scraping, so an image is not
  always available. The card always keeps the link and any text it could fetch,
  and tapping it retries the fetch.
- Share to app is wired for Android through the intent filters in
  `AndroidManifest.xml`. iOS additionally needs a Share Extension target added in
  Xcode, which is not included yet.
- `receive_sharing_intent` is pinned to 1.8.1. Version 1.9.0 requires a preview
  Android SDK and has a Gradle and Kotlin packaging issue. The pin is the reason
  for `kotlin.jvm.target.validation.mode=warning` in `android/gradle.properties`.
- `palette_generator` is marked discontinued upstream but still works. It can be
  replaced with a manual luminance sampler later if needed.
- Release signing secrets (`android/key.properties`, `android/key.properties.ready`,
  and `android/upload-keystore.jks`) are git ignored. Keep a private backup of
  the keystore, since losing it means you cannot ship updates to the same listing.
