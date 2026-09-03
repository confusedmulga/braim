# BRAIM

**OPERATOR'S HANDBOOK. PERSONAL NOTE AND JOURNAL SYSTEM.**

Publication BRAIM-1. Flutter airframe. Android primary, iOS secondary.

This handbook describes the operation of the Braim note system: a local-only
notebook, card file, writing desk, journal, and habit tracker that runs entirely
on the operator's device. No account is issued. No ground station is contacted.
All data remains on board.

Flutter package `braim`. Android application id and namespace `com.solo.braim`.
The on-device data file is named `keepy_data.json`, retained for backward
compatibility with earlier equipment.

## ADVISORY CONVENTIONS

Three advisories appear throughout this handbook. Observe them.

> **WARNING.** Failure to comply may result in loss of notes or exposure of
> private data.
>
> **CAUTION.** Failure to comply may result in a function not operating as
> intended.
>
> **NOTE.** Supplementary information provided to aid operation.

---

## SECTION I. GENERAL DESCRIPTION

1-1. Braim is a single-operator application. It holds notes, saved links and
tweets, long-form books, a dated journal, habit and goal trackers, and a focus
timer, all filed on the device.

1-2. The operator moves between five stations using the floating island at the
foot of the display. A universal action button is fitted to the right of the
island; its icon and function change with the active station. Swipe left or
right to change station. Re-tap the active station, or its greeting line, to
return its feed to the top.

1-3. A drawer is stowed off the left edge. Drag inward from the left edge, or
press the menu control at top left, to deploy it. The drawer provides access to
Settings, Archive, Recently Deleted, the Journal year view, the Reflex
trackers, the Pomodoro timer, and any folder.

1-4. A search field and a sort control are fitted across the top of the feed
stations. Search filters notes, cards, and folders as characters are entered.
Sort orders the feed by recently added (default), oldest first, alphabetical
A to Z, or alphabetical Z to A.

---

## SECTION II. STATIONS

### 2-1. HOME (Notes)

A masonry feed of notes. A single note may place multiple images between blocks
of text. Text supports Heading, Sub-heading, and Body sizes, plus bold, italic,
underline, and highlight, applied from a toolbar that targets the focused line.
Notes also carry tappable checklists and an optional colour tag. The first image
in a note becomes its feed thumbnail, with the folder name overlaid in black or
white according to contrast.

Press the pencil button to open a new note. Hold the pencil button to choose
between a quick **Note** and a long-form **Article**.

### 2-2. CARDS (Links and Tweets)

Saves tweets and links. Share a tweet to Braim from the Android share sheet, or
press the action button and paste a URL. The item becomes a card carrying a
best-effort preview. Tweets are fetched through Twitter/X oEmbed with no API
key, with the author avatar supplied by unavatar. Other links are read through
their Open Graph tags. Opening a card shows the fetched preview and the source
link, with a copy control, pinned at the top, and an editable note body beneath.
A saved article may be opened in **reader mode**, which extracts the article
text for clean reading. A card remains in Cards and, if assigned, also appears
in its folder.

### 2-3. NARRATIVE (Books)

A shelf of long-form books the operator is writing, with running totals of
books, pages, and words. Each book holds chapters and pages, a cover, and a
choice of reading typefaces (EB Garamond, Merriweather, Lora). Fitted functions
include find and replace across the book, chapter history, a distraction-free
reader view, and export to **PDF**, **Markdown**, or **ePub** through the share
sheet.

Press the action button to start a new book.

### 2-4. JOURNAL

A dated diary. A swipeable week strip runs across the top; hold it to expand the
month calendar. Each day carries three sections, whose order the operator may
rearrange: daily-day tasks, a reflex card, and diary entries. A year view is
reached from the drawer. Press the pencil button to add a daily task, a new
reflex, or a journal entry for the selected day.

### 2-5. CORTEX (Folders)

Folders that hold both notes and cards, shown as square, round-cornered tiles
with an uploadable cover photo and a contrast-matched label. A folder with a
cover opens with a header that collapses into the top bar as the feed scrolls; a
folder without one shows a plain titled bar. Hold any note or card to move it
into a folder. Press the action button to create a folder.

---

## SECTION III. ONBOARD SYSTEMS

### 3-1. REFLEXES (Habits and Goals)

Habit and goal tracking, reached from the drawer or the Journal. Each reflex
operates in one of three modes:

- **Daily.** The same threads recur every day. They reset each morning and the
  progress bar reports the current day's completion.
- **Checklist.** Threads are one-time milestones. Tick them off for good and the
  bar fills toward one hundred percent overall.
- **Long-term.** A tree of sections (for example, years), subsections (for
  example, subjects), and threads, for tracking a large objective such as a
  degree, plus a flat daily-reminder list.

Threads carry a priority flag (important, best, or optional). Reflexes may be
filtered by state (active, paused, done, archived) and by category, and an
analytics view reports progress over time.

### 3-2. POMODORO (Focus Timer)

A focus timer, reached from the drawer. Idle, it displays a tick-marked dial
with a pull-up sheet for the session length and Do Not Disturb. Running, the
display goes black and shows only the time remaining. The timer continues to run
in the background, carried by an ongoing notification, if the operator leaves the
application.

### 3-3. CRYPT (Locked Folder)

A special folder that opens only with a fingerprint or the device screen lock.
Its contents never appear in feeds or in search.

> **WARNING.** Crypt controls access only. Items inside it are stored unencrypted
> on the device and are included, readable, in every backup. Do not use Crypt for
> passwords, bank details, or other secrets.

### 3-4. ARCHIVE AND RECENTLY DELETED

Archiving hides an item without deleting it. Deleted items are held in Recently
Deleted for thirty days before permanent removal, and may be restored during
that period. Both are reached from the drawer.

### 3-5. WIKI-LINKS

Typing `[[Title]]` inside a note, journal entry, or card links it to another item
of the same title. Backlinks are shown on the linked item.

### 3-6. APPEARANCE

Appearance is set in Settings: System, Light, or Dark. System follows the device
theme. Light and dark wallpapers back the feeds. Body and reading typefaces are
selectable from the bundled font set.

### 3-7. BACKUP AND RESTORE

- **Local.** Export a single zip containing all data and images and share it to
  Drive, Files, or any target. Restore replaces the current contents from a
  chosen zip. A reminder banner appears on Home when data has not been backed up
  recently.
- **Google Drive.** An optional automated backup uploads the same zip into
  Google Drive's private application-data folder (the `drive.appdata` scope). It
  is invisible in the operator's Drive and holds only Braim's own files. Once
  connected, Braim also backs up silently when the application is sent to the
  background, throttled and skipped when nothing has changed, and keeps the five
  most recent backups. No Firebase is involved. See Section IV, 4-4 for setup.

> **CAUTION.** Losing the device without a backup loses the data. Braim keeps no
> server copy.

### 3-8. SHARE-IN

On Android, images, text, and links shared to Braim from other applications are
accepted through the intent filters in `AndroidManifest.xml`. Shared links become
cards; shared images and text become a note.

---

## SECTION IV. NORMAL OPERATION

### 4-1. Prerequisites

Flutter and the Dart SDK, with an Android emulator or a connected device. Tested
on Flutter 3.41 and Dart 3.11 against an Android emulator.

### 4-2. Fetch dependencies

```bash
flutter pub get
```

### 4-3. Run or build

```bash
flutter run                 # with an emulator or device attached
flutter build apk --debug   # produce an installable debug APK
```

### 4-4. Optional: enable Google Drive backup

Drive backup is off until a Google **Web application** OAuth client ID is
supplied. The client ID is a public identifier and carries no secret. Provide it
at build or run time:

```bash
flutter run --dart-define=BRAIM_GDRIVE_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Full one-time setup (Cloud project, Drive API, consent screen, signing
fingerprints) is given in [docs/google_drive_setup.md](docs/google_drive_setup.md).

> **NOTE.** Until a client ID is present, Settings shows "Drive backup not set
> up" and the rest of the application is unaffected.

---

## SECTION V. CONSTRUCTION

```
lib/
  l10n/          localized strings (app_en.arb) and generated bindings
  models/        Note, NoteBlock, Space, TweetCard, Book, Impulse, Annotation
  services/      storage, image picker, link preview, article extractor,
                 book export (PDF/Markdown/ePub), Drive backup, notifications,
                 Do Not Disturb, focus media, seed data, wiki links
  state/         AppState (ChangeNotifier) and the Pomodoro controller
  theme/         palette, note colours, and ThemeData
  widgets/       navigation island, top bar, search, note/card/folder tiles,
                 frosted chrome, sheets, and the open/close morph
  screens/       root shell, home, cards, books, journal, cortex, folder detail,
                 note and card editors, reflexes, pomodoro, archive, deleted,
                 settings
```

5-1. State is provided by `provider` through a single `AppState`
`ChangeNotifier`.

5-2. Persistence writes metadata to `keepy_data.json` in the application
documents directory, using an atomic temp, backup, rename sequence with a `.bak`
fallback on load. Picked images are copied into an `images/` subfolder and
referenced by path. Writes are debounced and run off the main isolate.

5-3. Label contrast uses `palette_generator` to find a thumbnail's dominant
colour. A luminance above 0.5 gives black text, otherwise white, cached per
image.

---

## SECTION VI. LIMITATIONS AND WARNINGS

6-1. **Tweet previews are best effort.** X restricts scraping, so an image is not
always available. The card always keeps the link and any text it could fetch,
and tapping it retries.

6-2. **Share-in is Android only.** iOS additionally requires a Share Extension
target added in Xcode, which is not yet included.

6-3. **`receive_sharing_intent` is pinned to 1.8.1.** Version 1.9.0 requires a
preview Android SDK and has a Gradle and Kotlin packaging issue. The pin is the
reason for `kotlin.jvm.target.validation.mode=warning` in
`android/gradle.properties`.

6-4. **`palette_generator` is marked discontinued upstream** but still works. It
may be replaced with a manual luminance sampler later.

> **WARNING.** Release signing secrets (`android/key.properties`,
> `android/key.properties.ready`, and `android/upload-keystore.jks`) are git
> ignored and are never committed. Keep a private backup of the keystore. Losing
> it means updates can no longer be shipped to the same store listing.

---

## LICENSE NOTE

Bundled fonts (Lora, Caveat, Space Grotesk, EB Garamond, Merriweather, Inter,
Nunito) are distributed under the SIL Open Font License. Each license file
travels with its font under `assets/fonts/`.
