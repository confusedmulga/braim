# BRAIM

**OPERATOR'S HANDBOOK. PERSONAL NOTE AND JOURNAL SYSTEM.**

Publication BRAIM-1. Flutter airframe. Android primary, iOS secondary.

This handbook describes the operation of the Braim note system: a local-only
notebook, card file, writing desk, journal, and habit tracker that runs entirely
on the operator's device. No account is issued. No ground station is contacted.
All data remains on board.

Flutter package `braim`. Android application id and namespace `com.solo.braim`.
On-device data is held in a local SQLite database (`braim.db`). The earlier
single-file store, `keepy_data.json`, is retained as the backup and export
format and as a one-time import source, and is never deleted.

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
trackers, the Focus timer, and any folder.

1-4. A search field and a sort control are fitted across the top of the feed
stations. Search filters notes, cards, and folders as characters are entered;
notes and cards are ranked by relevance, each word matches from its start, and
accents are ignored.
Sort orders the feed by recently added (default), oldest first, alphabetical
A to Z, or alphabetical Z to A. The sort panel also carries a "Filter by tag"
control listing every tag in use; pick one to show only the notes that carry it,
or "All tags" to clear it. The Home feed shows the active tag as a chip that
clears on a tap. The same tags are listed under the Home entry in the drawer:
tap the arrow beside Home to open them and pick one to filter the feed.

1-5. Inside a folder the sort control is folded into the search button. Press and
hold the search button to open the same sort and tag options for that folder.

---

## SECTION II. STATIONS

### 2-1. HOME (Notes)

A masonry feed of notes. A single note may place multiple images between blocks
of text. Text supports Heading, Sub-heading, and Body sizes, plus bold, italic,
underline, and highlight, applied from a toolbar that targets the focused line.
Notes also carry tappable checklists and an optional colour tag. The first image
in a note becomes its feed thumbnail, with the folder name overlaid in black or
white according to contrast. Images added to a note open in a built-in cropper
before they are saved; back out of the cropper to keep the original.

Notes come in two kinds. The **rich note** described above uses the handwriting
face and a formatting toolbar. A **Markdown document** instead renders
GitHub-flavored Markdown for reading and switches to a monospace source editor,
with a live preview, for writing. Any note may be shared out as a `.md` file or
exported to **PDF** through the share sheet, and a `.md` or `.txt` file shared
into Braim is saved as a note.

Press the pencil button to open a new rich note. Hold it for a short menu: a new
**circuit** (a note that grows into a tree, described in 3-10), a new **Markdown
document**, **import** a `.md` or `.txt` file, or a plain new note.

### 2-2. CARDS (Links and Tweets)

Saves tweets and links. Share a tweet to Braim from the Android share sheet, or
press the action button and paste a URL. The item becomes a card carrying a
best-effort preview. Tweets are fetched through Twitter/X oEmbed with no API
key, with the author avatar supplied by unavatar. Other links are read through
their Open Graph tags. A saved **YouTube** link takes its title, channel and
thumbnail from YouTube's official oEmbed endpoint, with no API key; the watch
page itself is never fetched. Opening a card shows
the fetched preview and the source link, with a copy control, pinned at the top,
and an editable note body beneath. A saved article may be opened in **reader
mode**, which extracts the article text for clean reading. A card also exports to
**PDF** through the share sheet. A card remains in Cards and, if assigned, also
appears in its folder.

### 2-3. NARRATIVE (Books)

A shelf of long-form books the operator is writing, with running totals of
books, pages, and words. Each book holds chapters and pages, a cover cropped to
shape, and a choice of reading typefaces (EB Garamond, Merriweather, Lora). Fitted functions
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
folder without one shows a plain titled bar, and its feed slides up under that
bar behind a soft fade. Hold any note or card to move it into a folder. Press
the action button to create a folder.

Each folder has a "Hide from feeds" switch. Turn it on to keep that folder's
notes and cards out of Home and Sparks; they still show inside the folder itself
and remain findable through search. Only the two feed listings leave them out.
Their tags also drop out of the tag filter, so the filter never lands on an empty
feed.

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
analytics view reports progress over time. A consistency heatmap on each reflex
opens a month-by-month history: every day with scheduled threads is shaded by
how many were completed, and tapping a day shows that day's tally.

### 3-2. FOCUS TIMER

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
theme. Original light and dark artwork backs the feeds, or the operator may pick
an image of their own for each theme. Body and reading typefaces are
selectable from the bundled font set.

### 3-7. BACKUP AND RESTORE

- **Manual.** Export a single zip of all data and images two ways: **Save to
  device** writes it through the system save dialog (Files, an SD card, other
  local providers), and **Send a copy** hands it to the OS share sheet, which
  offers Google Drive, email and any other app — the reliable route for an
  off-device copy. Restore replaces the current contents from a chosen zip. A
  reminder banner appears on Home when data has not been backed up recently.
- **Automatic on device.** A switch keeps a zip copy on a schedule of daily,
  weekly, or monthly. It runs when the application is sent to the background and
  is skipped when nothing has changed. Copies land in the application's own
  private storage; the five most recent are kept and older ones are removed
  automatically. This storage guards against a bad write, but Android clears it
  if Braim is uninstalled and it is lost with the device, so it does not replace
  a copy kept elsewhere (an export).

> **CAUTION.** Losing the device without a backup loses the data. Braim keeps no
> server copy.

### 3-8. SHARE-IN

On Android, images, text, and links shared to Braim from other applications are
accepted through the intent filters in `AndroidManifest.xml`. Shared links become
cards; shared images and text become a note.

### 3-9. REMINDERS AND NOTIFICATIONS

A note may carry a dated reminder, reflex threads may raise a daily prompt, and
the journal has an optional nightly nudge, all delivered as device notifications.
Settings carries a **Test notifications** control that sends one notification
immediately and a second ten seconds later, then reports which of them the
operating system delivered, so notification permission and Do Not Disturb can be
checked without waiting for a real reminder.

### 3-10. CIRCUITS

A circuit is a note that grows into a tree. It begins as one full note, the
first note, and every branch under it is a full note of its own, rich or
Markdown, nested to any depth. The first note appears in the Home feed as a
**Circuit** card counting the notes inside it; the branches stay out of the feed
unless one is set to show there.

Start a circuit from the Home pencil menu (2-1). Inside any circuit note the top
bar carries a **plus**, which adds a note next to or under the current one, and a
**map** button. The map is a full-screen canvas that pans and pinch-zooms and
lays the tree out three ways, **left to right**, **top down**, and **radial**,
switched from the top bar and remembered per circuit. Tap a node to open it. The
plus on the outer edge of a node adds a child. Long-press a node for its actions:
rename, colour, move up or down, move into the note above or out one level, move
to another branch, add or place notes, show or hide it in the Home feed, remove
it from the circuit, or delete it.

Every new note inside a circuit is titled "Note #1", "Note #2" and so on, so it
is never an empty note that the cleanup could remove. Deleting a note that has
notes under it offers to delete the whole subtree or to keep a titled
**placeholder** in its place so the notes under it stay attached; a placeholder
can later be written into, filled with an existing note, or removed. Deleting the
first note deletes the whole circuit. A branch shown in the Home feed carries an
"In {circuit}" chip, and circuit notes are found by search and can be linked with
`[[wiki-links]]`. Circuits follow their first note into a folder, the Archive or
Recently Deleted, and are never placed in the Crypt.

**NOTE.** Restoring a backup into an older build of Braim that predates circuits
shows the circuit notes as ordinary loose notes in the feed. Nothing is lost;
reopening that backup in a current build restores the tree.

### 3-11. BRAIM WEB

Braim Web opens the library in a browser on a computer. The phone itself is the
server: the pages travel over the local network from the phone to the computer
and nowhere else, so the phone must be switched on, in reach, and running Braim
while the computer is in use.

**Starting.** In Settings, under **Braim Web**, switch on **Open Braim on your
computer**. The phone and the computer must be on the same Wi-Fi network. The
panel shows an address such as `http://192.168.1.23:8420`; type it into the
computer's browser. While Braim Web is on, a notification stays in the phone's
shade with a **Turn off** button.

**Pairing.** The first visit from a browser asks for the six-digit pairing code
shown in the panel. A code lasts two minutes and is replaced by a fresh one after
each use. Five wrong entries lock pairing for thirty seconds. A paired browser
stays linked until it goes thirty days unused, and at most five browsers may be
linked at once. **Linked browsers** in the panel lists them, with **Log out** for
each and **Log out all**; a browser logged out is returned to the pairing page.
If the phone's address changes (another network, or a new address from the
router), open the new address and pair again.

**Auto-off.** Braim Web turns itself off after thirty minutes without use. A tab
left open and in view counts as use; a hidden tab does not. Swiping Braim away
from Recents also turns it off.

**On the computer.** The site is laid out as a desktop: a menu bar with the
Braim logo, a **File** menu and one title for each section, **Notes**,
**Sparks**, **Circuits** and **Books**, and every item in a window of its own.
The Notes page carries three small desk accessories above its window: the date
and the link to the phone, a clock, and a Game of Life.

- Notes and sparks are read, created, edited and deleted. Checklists tick from
  the reading view. Markdown notes are edited as source, with a preview.
- A note's tags and colour are set under its title in the editor. Photos are
  added to a rich note from the computer, up to 10 MB each (JPEG, PNG, GIF or
  WebP), and removed with the button on each photo.
- **Print…** in the File menu prints the open note, spark, chapter or book on
  plain paper, a book one page to a sheet.
- Circuits open on their map, which drags to pan and zooms with the wheel or a
  pinch, switches between the three layouts, and carries each note's actions on
  its menu: add, rename, move up or down, delete, and the placeholder actions.
- Books open on their contents, where chapters are added, moved up or down, read
  in the book's typeface, and edited.
- Search covers notes and sparks. Changes made on the phone appear on the
  computer within a second or two.
- Keys: `/` searches, `e` edits the open note or spark, `Ctrl+S` saves, and
  `Esc` leaves the editor. Editing saves itself a moment after typing stops.

**One editor at a time.** A note, spark or book page open for editing on one
side opens read-only on the other, and says where it is being edited, so neither
side's autosave can overwrite the other. It frees up when that editor closes.

**Not on the computer.** The Crypt is never served: its notes, sparks and images
answer as if they did not exist, and never appear in search. Journal entries,
archived items, Recently Deleted, reflexes, settings, workshop notes, covers and
exports stay on the phone, as do deleting book pages and the circuit actions not
listed above.

> **TIP.** Where there is no shared Wi-Fi, turn on the phone's hotspot and join
> it from the computer. Braim Web works over the hotspot the same way.

> **WARNING.** The connection is plain HTTP and is not encrypted. Anyone on the
> same network could read the pages as they pass. Use Braim Web only on networks
> the operator trusts, such as a home network or the phone's own hotspot, and
> never on public Wi-Fi.

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

---

## SECTION V. CONSTRUCTION

```
lib/
  l10n/          localized strings (app_en.arb) and generated bindings
  models/        Note, NoteBlock, Space, TweetCard, Book, Impulse, Annotation
  services/      SQLite store and one-time JSON importer (services/db), JSON
                 storage and export, note to/from Markdown, note/card PDF export,
                 image picker, link preview, article extractor, YouTube oEmbed,
                 book export (PDF/Markdown/ePub), notifications,
                 Do Not Disturb, focus media, seed data, wiki links
  state/         AppState (ChangeNotifier) and the Pomodoro controller
  web/           Braim Web: the HTTP server, pairing and sessions, the page
                 builders and JSON API, live updates, and the controller the
                 Settings switch drives
  theme/         palette, note colours, and ThemeData
  widgets/       navigation island, top bar, search, note/card/folder tiles,
                 Markdown view, frosted chrome, sheets, and the open/close morph
  screens/       root shell, home, cards, books, journal, cortex, folder detail,
                 rich and Markdown note editors, card editor, image cropper,
                 reflexes, reflex history, pomodoro, archive, deleted, settings
```

5-1. State is provided by `provider` through a single `AppState`
`ChangeNotifier`.

5-2. The primary on-device store is a local **SQLite** database (`sqflite`),
`braim.db`, in the application documents directory. The full library is loaded
into memory at startup, and feeds, sorting, and backlinks are served from memory.
Each save writes only the changed rows (a dirty-diff flush), debounced and run
off the main isolate. Picked images are stored as files in an `images/` subfolder
and referenced by path, never held in the database.

5-3. On first launch after upgrading, the earlier `keepy_data.json` store is read
once and imported into the database, verified by row count, and never deleted. If
the import or the database ever fails, the application falls back to the JSON
store, so no data is lost. The JSON format also remains the backup and export
artifact, so existing backups restore unchanged. Full detail is in
[docs/sqlite-migration-plan.md](docs/sqlite-migration-plan.md).

5-4. Full-text search is backed by an FTS5 index, ranked and accent-insensitive,
falling back to an in-memory filter where FTS5 is unavailable.

5-5. Label contrast uses `palette_generator` to find a thumbnail's dominant
colour. A luminance above 0.5 gives black text, otherwise white, cached per
image.

5-6. Braim Web (3-11) is a `shelf` HTTP server running in the application's
main isolate beside `AppState`, so a change made in the browser goes through the
same methods as a tap on the phone. A foreground service of type
`connectedDevice` keeps it reachable while the screen is off. The browser side is
plain HTML, CSS and a few small scripts in `assets/web/`, with the Quill editor
vendored in `assets/web/vendor/`; there is no build step. Full detail is in
[docs/braim-web-plan.md](docs/braim-web-plan.md).

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

## CONTRIBUTORS

- **Kalpesh Nichal**: author and publisher of Braim on Google Play.
- **Ananya** ([@ananyaroys](https://github.com/ananyaroys)): contributor.

## LICENSE NOTE

The MIT License in `LICENSE` covers the source code written for Braim. It does
not cover:

- **The Braim name and logo.** All rights reserved. The logo was drawn by
  Kalpesh Nichal in Affinity Designer (sources in `assets/logos/`).
- **The focus-timer artwork** (`android/app/src/main/res/drawable-nodpi/focus_art.png`),
  drawn as SVG for Braim by Claude, an AI model by Anthropic.
- **Bundled fonts** (Lora, Caveat, Space Grotesk, EB Garamond, Merriweather,
  Inter, Nunito, JetBrains Mono), distributed under the SIL Open Font License
  with their license files under `assets/fonts/`. JetBrains Mono is used only for
  code, in exported PDFs and on Braim Web.
- **Quill** (`assets/web/vendor/`), the editor Braim Web uses, under the BSD
  3-Clause License, with the notices of the packages its build bundles, in
  `assets/web/vendor/LICENSE-quill.txt`.
- **The feed wallpapers** (`assets/wallpapers/lightmain.PNG` and
  `darkmain.PNG`), original artwork made for Braim. All rights reserved.
- **Dart and Flutter packages**, each under its own license, listed in the app
  under Settings › About › Open-source licenses.

The [Privacy Policy](PRIVACY.md) and [Terms of Use](TERMS.md) are linked from
Settings › About. Braim is not affiliated with X, YouTube, Google or unavatar.io;
avatars are provided by [Unavatar](https://unavatar.io).
