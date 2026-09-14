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
**Markdown document**, **import** a `.md` or `.txt` file, or a plain new note.

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

- **On device.** Export a single zip of all data and images. The system save
  sheet writes it to Files, Drive, an SD card, or any target, so one action
  covers both a local and a cloud copy. Restore replaces the current contents
  from a chosen zip. A reminder banner appears on Home when data has not been
  backed up recently.
- **Automatic on device.** A switch keeps a zip copy on a schedule of daily,
  weekly, or monthly. It runs when the application is sent to the background and
  is skipped when nothing has changed. Copies land in the application's own
  private storage; the five most recent are kept and older ones are removed
  automatically, the same retention as the Drive copies. This storage guards
  against a bad write, but Android clears it if Braim is uninstalled and it is
  lost with the device, so it does not replace a copy kept elsewhere (an export
  or the Drive backup).
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

### 3-9. SIGNING IN WITH GOOGLE

Signing in with a Google account has one purpose: automatic backup to that
account's Google Drive. It is optional and changes nothing else about how Braim
operates on the device.

On sign-in:

- **Scope.** Braim requests one permission only: `drive.appdata` (its own
  private Drive folder). The connected account is identified by its email address
  alone; no profile scope is requested, so no name or photo is fetched or shown.
  Braim cannot see, read, or touch any other file in the operator's Drive.
- **Destination.** Backups go to Drive's hidden application-data folder — not a
  folder the operator picks, and invisible in the Drive interface. Only Braim
  can see it. It never clutters the operator's Drive.
- **Routine.** Daily automatic backup switches on. Braim uploads a zip of the
  whole library (notes, cards, books, journal, reflexes) silently when the app
  is sent to the background — about once a day, and only when something has
  changed since the last upload.
- **Retention.** The five most recent backups are kept; older copies are removed
  automatically.
- **Manual control.** "Back up now" and "Restore" (from any of the five copies)
  live in Settings. Auto-backup can be switched off, and the account
  disconnected, at any time.

No password is handled by Braim, no server operated by the developer is
contacted, and nothing leaves the device except the backup zip, which goes to
the operator's own Drive.

### 3-10. REMINDERS AND NOTIFICATIONS

A note may carry a dated reminder, reflex threads may raise a daily prompt, and
the journal has an optional nightly nudge, all delivered as device notifications.
Settings carries a **Test notifications** control that sends one notification
immediately and a second ten seconds later, then reports which of them the
operating system delivered, so notification permission and Do Not Disturb can be
checked without waiting for a real reminder.

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
  services/      SQLite store and one-time JSON importer (services/db), JSON
                 storage and export, note to/from Markdown, note/card PDF export,
                 image picker, link preview, article extractor, YouTube scraper,
                 book export (PDF/Markdown/ePub), Drive backup, notifications,
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
