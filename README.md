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
trackers, the Pomodoro timer, and any folder.

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
their Open Graph tags. A saved **YouTube** link is scraped, with no API key, for
the video's title, channel, description, and caption transcript, shown in
collapsible Description and Transcript panels on the card. Opening a card shows
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

### 3-11. ON A COMPUTER (WEB APP)

The same app, same screens, runs in Chrome, Edge or Firefox on a PC, in a
phone-width column over the blurred wallpaper. It works two ways from one build.

- **Open on computer (the phone's library, live).** On the phone, Settings →
  **Open on computer** starts a small server inside Braim and shows an address
  and a QR code. On a computer joined to the same Wi-Fi, or to the phone's own
  hotspot, open that address. The phone asks whether to allow the computer; once
  allowed, the browser shows the phone's library and every edit on either side
  appears on the other within a second. The browser keeps no copy: the phone
  stays the only library. **Remember this computer** skips the question next
  time; the phone lists paired computers with **Forget**. The server stops from
  the same sheet, when Braim closes, or after 15 minutes with no computer
  connected, and keeps the phone's screen on while it runs.
- **In the browser alone (its own library).** Served from anywhere else (a
  static host, or with `?mode=local`), the browser keeps its own library in its
  storage. Bring the phone's notes over with **Import backup from phone** (a
  backup zip from 3-7), and take them back with **Export backup (.zip)**, which
  the phone restores with its normal restore.

The **Crypt** never leaves the phone's lock. A phone-served browser asks the
phone, which unlocks with its own biometrics; the Crypt then stays open there
until 10 minutes pass without activity. A browser-only library never holds it.
Theme, wallpaper, sort and similar choices belong to each computer and never
change the phone's.

On a computer: **right-click** does what a long-press does; **Esc** goes back;
**Ctrl+K** or **/** searches; **Ctrl+N** creates on the current tab;
**Ctrl+Enter** finishes editing; **← →** switch tabs. The mouse can drag between
tabs.

> **CAUTION.** A browser-only library lives in the browser's storage. Clearing
> site data erases it; export a backup now and then.

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

### 4-4. Build the web app

```bash
python3 tool/fetch_web_fonts.py     # fallback fonts, served from the app's own origin
flutter build web --release --no-web-resources-cdn

tool/build_web_bundle.sh            # put the web app inside the APK for "Open on computer"
flutter build appbundle             # (run the line above first, every release)
```

`--no-web-resources-cdn` keeps the rendering engine in the build instead of
loading it from Google's CDN, and the fetched fonts replace Google Fonts, so
nothing is requested from the internet when a computer uses the phone's hotspot.
The bundle adds about 11 MB to the APK. Without it, "Open on computer" serves a
page saying the web app is missing; everything else is unaffected.

### 4-5. Check the web app

```bash
flutter test                                      # includes the phone server tests
node tool/web_smoke.mjs build/web                 # browser-only library, in Chromium
node tool/remote_smoke.mjs build/web              # phone-served, against a stand-in phone
```

Both scripts need Playwright with Chromium. They import a fixture backup built
from `test_data/`, take screenshots of every main screen in light and dark, and
fail if any request leaves the machine.

---

## SECTION V. CONSTRUCTION

```
lib/
  l10n/          localized strings (app_en.arb) and generated bindings
  models/        Note, NoteBlock, Space, TweetCard, Book, Impulse, Annotation
  services/      SQLite store and one-time JSON importer (services/db), JSON
                 storage and export, note to/from Markdown, note/card PDF export,
                 image picker, link preview, article extractor, YouTube scraper,
                 book export (PDF/Markdown/ePub), notifications,
                 Do Not Disturb, focus media, seed data, wiki links
  state/         AppState (ChangeNotifier) and the Pomodoro controller
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

6-5. **The phone-served web app is plain HTTP.** Anyone on the same network can
read the traffic. Use the phone's hotspot or a Wi-Fi you trust. Pairing needs a
single-use code from the phone's screen and the owner's approval on the phone.

6-6. **Open on computer works while Braim is open on the phone.** The screen is
kept on while the server runs; Android may stop the server if Braim is closed or
the phone is put away for long.

6-7. **After a minute out of reach of the phone, the browser stops taking
edits** until the phone is back (it holds no durable copy). Changes made before
that are sent when it reconnects.

6-8. **In a browser-only library, link previews wait for the phone.** Browsers
can't read other sites, so a link saved there shows as a plain link until the
library is restored on the phone. Phone-served browsers ask the phone to fetch.

6-9. **Chinese, Japanese and Korean text** isn't bundled (those fonts are about
60 MB). The phone-served app fetches them from Google when the computer is
online. For a browser-only build that must show them, fetch them into the build
with `python3 tool/fetch_web_fonts.py --all`.

> **WARNING.** Release signing secrets (`android/key.properties`,
> `android/key.properties.ready`, and `android/upload-keystore.jks`) are git
> ignored and are never committed. Keep a private backup of the keystore. Losing
> it means updates can no longer be shipped to the same store listing.

---

## LICENSE NOTE

Bundled fonts (Lora, Caveat, Space Grotesk, EB Garamond, Merriweather, Inter,
Nunito, JetBrains Mono) are distributed under the SIL Open Font License. Each
license file travels with its font under `assets/fonts/`. JetBrains Mono is used
only for code in exported PDFs.
