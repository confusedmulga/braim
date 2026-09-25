# Web App Plan (Braim)

A build reference for running Braim in a desktop browser: the same app, same
screens, same look, on a PC screen. The web app must work in two modes from one
codebase:

- **Remote mode (Option 1).** The phone serves the web app and its data over the
  LAN (home Wi-Fi or the phone's hotspot). The browser holds no durable copy;
  the phone's SQLite library is the only source of truth.
- **Local mode (Option 2 foundation).** The web app runs standalone with its own
  copy of the library in the browser (SQLite compiled to WASM on IndexedDB).
  Seeded from a phone backup zip for now. Real phone <-> browser sync is a later
  project; this plan only has to leave the door open for it.

No cloud, no accounts, no third-party server holds data in either mode.

Follow the phases in order. Do not start a phase until the previous phase's
checklist is ticked and `flutter test` plus an Android debug build are green.
**The Android app must behave identically after every phase** — the web work is
additive, gated behind `kIsWeb` or injected implementations, never a rewrite of
mobile behaviour.

---

## 1. Goals and non-goals

### Goals
- Every screen, flow and visual the phone has, rendered in Chrome/Edge/Firefox
  on a PC: feeds, spaces, cards, notes + editor, markdown notes, circuits and
  the circuit map, books + reader + chapter history, journal + year view,
  reflexes + daily day + analytics, pomodoro, search, archive, recently deleted,
  settings.
- One codebase, one `AppState`, one widget tree. No forked screens.
- Two storage backends behind one interface: remote (phone) and local (browser).
- Works fully offline once loaded (remote mode needs only the LAN).
- Mouse, keyboard and right-click behave like a desktop app would expect.

### Non-goals (out of scope for this plan)
- Merging edits made independently on phone and browser (Option 2 sync, HLC
  clocks, conflict copies). Separate plan, later.
- A redesigned wide/desktop layout. v1 keeps the phone layout (see §2.1).
- Web push notifications, Android share-intent equivalents, DND, media session.
- Any hosted backend. Hosting *static code* for local mode is discussed in §2.2
  but no data ever leaves the user's devices.

---

## 2. Decisions

Recommendations are marked. Confirm the ones marked **(confirm)** with Kalpesh
before starting the phase that needs them.

### 2.1 Layout on a PC screen **(confirm)**
The UI is built for ~360–430 dp wide portrait. Stretching it to 1440 px wide
breaks feeds (two giant masonry columns), the island nav, the side pane push
and the glass chrome.

**Recommended:** render the app in a centred phone-width column
(`maxWidth: 480`, full browser height) with the active feed wallpaper blurred
and extended as the page backdrop behind it. Pixel-identical to the phone,
zero per-screen layout work. A wider "desktop layout" (multi-column feed,
editor beside list) is a later, optional phase (§13, Phase 7).

Implementation: one wrapper in `MaterialApp.builder` (web only) that
constrains width and supplies a `MediaQuery` whose `size` is the constrained
size, so every `MediaQuery.of(context).size` read in the screens sees a phone.

### 2.2 Where the local-mode web bundle is served from **(confirm)**
- Remote mode: the phone serves the bundle. Settled.
- Local mode needs the bundle from somewhere when the phone is not around, and
  an installable offline PWA requires a **secure context** (HTTPS or
  `http://localhost`). A page served by the phone over plain `http://192.168…`
  is not a secure context: no service worker, no install, no `crypto.subtle`,
  no OPFS.
- Options: (a) GitHub Pages / any static host — code only, installs as a PWA,
  data stays in the browser; (b) `http://localhost` from a tiny local static
  server on the PC (a desktop install, which defeats "web app"); (c) open the
  phone-served URL and accept no offline install.
- **Recommended:** (a). It hosts code, never notes. Revisit if Kalpesh wants
  zero hosting of any kind — then local mode only works while the page stays
  open or is re-served by the phone.

### 2.3 Crypt on the web **(confirm)**
Crypt items are ordinary rows gated by `local_auth` (`lib/services/crypt_auth.dart`),
not encrypted at rest. `local_auth` has no web implementation, and
`authenticateForCrypt` returns `false` on any throw, so the web would lock the
user out — or, if naively stubbed to `true`, expose Crypt to anyone at the PC.
- Remote mode (**recommended**): the phone never sends Crypt-space rows
  (`spaceId == kCryptSpaceId`, and circuit branches whose root is in Crypt)
  until an unlock request is approved *on the phone* with the phone's
  biometric prompt. The unlock is per browser session and expires on idle
  (10 min).
- Local mode (**recommended for v1**): Crypt rows are excluded from the browser
  copy on import. A later option is a passphrase-derived key encrypting Crypt
  bodies at rest (needs a secure context for `crypto.subtle`, or a pure-Dart
  cipher).

### 2.4 Renderer
Build with the default CanvasKit renderer first (`flutter build web`). Try the
WASM build (`--wasm`, skwasm renderer) once everything works — it is faster for
the heavy `BackdropFilter`/glass use but requires every dependency to be
WASM-compatible (no `dart:html`, `package:js`). Keep whichever passes §14.

---

## 3. How the app is built today (facts this plan rests on)

- **`AppState` is the only seam the UI talks to.** `lib/state/app_state.dart`
  (~4.5k lines) holds the whole library in memory (`_notes`, `_spaces`,
  `_cards`, `_books`, `_impulses` + ~30 settings). Screens read it through
  Provider (`context.watch/select<AppState>`). Screens do *not* touch the DB.
- **One persistence path.** Every mutation ends in `_persist()` → bumps `_rev`,
  notifies, and coalesces a `_flush()` 400 ms later. `_flush()` builds
  `_snapshot()` (an `AppData`) and calls `DbStore.syncFromAppData(snapshot)`.
- **`DbStore` already computes row-level deltas.** `lib/services/db/db_store.dart`
  keeps a `_baseline` of `"<table>:<id>" → body` and each sync writes only
  changed/added rows, deletes rows that vanished, and upserts changed settings
  keys. Rows are `{id, updated_at, created_at, archived, deleted_at, …, body}`
  where `body` is the entity's full JSON (`lib/services/db/db_snapshot.dart`).
  **This delta engine is exactly what remote mode needs to send over the wire.**
- **Soft vs hard delete.** Trash is a soft delete (`deletedAt` in the body).
  Permanent delete / purge removes the row — surfaces as a `delete` in the diff.
- **Startup.** `AppState.init()` → `DbStore.init()` (one-time JSON import) →
  `readAppData()` or legacy JSON → `_applyData()` (populate lists, purge expired
  trash, `_repairCircuits()`, drain share inbox, reschedule notifications,
  background link-preview enrichment).
- **Images are absolute file paths** stored in the models:
  `NoteBlock.imagePath`, `Space.thumbnailPath`, `Book.coverPath`,
  `feedBackgroundLight/Dark`, `journalMonthCovers` values. Files live in
  `<appDocs>/images/<uuid>.<ext>` (`StorageService.saveImage/saveImageBytes`).
  Rendered with `Image.file(File(path))` in 11 files.
- **`dart:io` is imported in 22 files under `lib/`** (list in §5.1). 41 `File(`
  call sites.
- **Remote images** (`TweetCard.imageUrl`, avatars, YouTube thumbnails) use
  `Image.network` in `tweet_card_widget.dart`, `card_detail_screen.dart`,
  `note_body_editor.dart`, `thumbnail_label.dart`.
- **Outbound HTTP** (`package:http`) in `link_preview_service.dart`,
  `youtube_service.dart` (+ `article_extractor.dart` parsing the result).
- **Native Android pieces**: `MainActivity.kt`, `ShareActivity.kt` (share
  popup engine, `shareMain()` entry point), `FocusMedia.kt`; channels
  `braim/dnd`, `braim/media`, `braim/share`.
- **Platform plugins in use**: sqflite, path_provider, image_picker,
  receive_sharing_intent, file_picker, share_plus, printing, pdf, local_auth,
  flutter_local_notifications, flutter_timezone, timezone, url_launcher,
  flutter_quill, crop_your_image, palette_generator, archive.
- **Assets**: ~18 MB of top-level wallpapers + ~2.7 MB fonts (the `assets/`
  entry bundles top-level files only; `assets/logos/` is not bundled).
- There is **no `web/` folder** yet and no Flutter SDK in the cloud container
  (install it first — §14.1).

---

## 4. Target architecture

```
                         ┌──────────────── UI (unchanged screens) ───────────────┐
                         │         Provider<AppState>  +  DesktopFrame (web)     │
                         └───────────────────────────┬───────────────────────────┘
                                                     │ same API as today
                                              ┌──────┴──────┐
                                              │  AppState   │  in-memory library
                                              └──────┬──────┘
                          load() / push(delta) / search() / incoming changes
                                              ┌──────┴──────┐
                                              │LibraryStore │  (new interface)
                                              └──────┬──────┘
               ┌──────────────────────────────┬──────┴─────────────────────────┐
     DeviceLibraryStore (Android)    WebLocalLibraryStore             RemoteLibraryStore
     DbStore + StorageService JSON   DbStore on sqflite-wasm           WebSocket/HTTP to phone
     (exactly today's behaviour)     + IndexedDB image blobs           + phone-served images
                                                                             │
                                                              ┌──────────────┴─────────────┐
                                                              │ PhoneServer (Android only) │
                                                              │ dart:io HttpServer on LAN  │
                                                              │ talks to the phone's own   │
                                                              │ AppState                   │
                                                              └────────────────────────────┘
```

Plus a set of small **platform services** (§5) so screens stop reaching for
`dart:io`, `File`, plugins and channels directly.

### 4.1 `LibraryStore` interface (new, `lib/services/store/library_store.dart`)

```dart
typedef RowChange = ({String table, String id, Map<String, Object?>? row}); // row == null → hard delete
class LibraryDelta {
  final List<RowChange> rows;
  final Map<String, String> settings; // key -> JSON value
}

abstract class LibraryStore {
  Future<void> init();
  Future<AppData> load();                       // whole library at startup
  Future<bool> push(AppData snapshot);          // diff vs baseline, persist/send
  Future<List<SearchHit>?> search(String q);    // null → in-memory fallback
  Stream<LibraryDelta> get incoming;            // changes made elsewhere (remote)
  Future<void> flush();                         // app pause / tab hidden
  StoreCapabilities get caps;                   // what the UI may offer (§5.3)
}
```

- Extract the diff logic out of `DbStore.syncFromAppData` into a pure
  `SnapshotDiffer` (`baseline`, `diff(AppSnapshot) → LibraryDelta`,
  `commit(LibraryDelta)`, `reseed(AppSnapshot)`). `DbStore` uses it to write
  SQLite; `RemoteLibraryStore` uses it to build the wire payload. Unit-test the
  differ on its own (existing `db_store_test.dart` must stay green unchanged).
- `AppState` takes `LibraryStore` instead of `DbStore` in its constructor.
  `DeviceLibraryStore` wraps today's `DbStore` + `StorageService` JSON logic
  (`init`'s import/jsonAhead dance, `_flush`, `flushNow` checkpoints) so the
  Android path is byte-for-byte the same behaviour. Move code, don't rewrite it.
- `AppState` gains `applyIncoming(LibraryDelta)`: replace/insert/remove entities
  by id in the in-memory lists, apply settings keys, `_rev++`, `notifyListeners()`,
  and tell the store's differ to adopt those rows into its baseline **so they are
  not echoed back** on the next `push`.

### 4.2 Boot and mode selection (`lib/main.dart`)

```
main()
 ├─ !kIsWeb → today's main (notifications init, DND restore, SystemChrome) with DeviceLibraryStore
 └─ kIsWeb  → skip notification/DND/SystemChrome init
              mode = await detectMode()
                 GET /api/hello on the page's own origin (1.5 s timeout)
                   200 + {"app":"braim"} → remote (served by a phone)
                   otherwise             → local
              store = remote ? RemoteLibraryStore(origin) : WebLocalLibraryStore()
              runApp(BraimApp(store: store))   // BraimApp creates AppState(store:)
```

- `?mode=local` query parameter forces local mode for testing.
- Remote mode shows a pairing screen before `RootShell` if there is no valid
  session (§10.2). Local mode with an empty library shows an "Import a backup
  from your phone" empty state (§11.3) instead of seed data.
- `shareMain()` stays Android-only.

---

## 5. Platform services

### 5.1 Every `dart:io` / plugin touchpoint and its web replacement

Rule: no file outside `lib/platform/` and the three stores may import
`dart:io` or a mobile-only plugin. Use conditional imports
(`import 'x_io.dart' if (dart.library.js_interop) 'x_web.dart';`) — do not rely
on the web `dart:io` stub (it throws at runtime and does not exist under
`--wasm`).

| Where today | What it does | Android | Web remote | Web local |
|---|---|---|---|---|
| `services/storage_service.dart` | JSON file store, images dir, share inbox, jsonAhead flag | as is | n/a (phone owns) | n/a |
| `services/db/*` | sqflite | as is | n/a | sqflite web (`sqflite_common_ffi_web`), same `DbStore` |
| `services/image_service.dart` | `image_picker` → copy file → path | as is | pick → bytes → `PUT /api/image` | pick → bytes → IndexedDB |
| `Image.file(File(p))` ×13 in 11 files | show stored image | as is | `BraimImage` → `/api/image/<name>` | `BraimImage` → IndexedDB blob → `Image.memory` |
| `screens/crop_screen.dart` | `File(src).readAsBytes()` | as is | bytes in, bytes out | same |
| `services/backup_service.dart`, `state/app_state.dart` backup bits | zip export/restore, auto-backup on pause | as is | hidden (phone owns backups) | "Export backup (.zip)" download, "Import backup" upload |
| `screens/settings_screen.dart` | backup/restore, notifications, auto-backup rows | as is | hide by caps | hide by caps; add Import/Export |
| `screens/root_shell.dart` | share intent stream, `_importFile` via `File(path)`, lifecycle | as is | no share intent; `file_picker` `withData: true` | same |
| note/markdown/card/circuit screens `.md` export | write temp file → `share_plus` | as is | `FileSaver.save(bytes, name)` → browser download | same |
| `services/book_export.dart` | epub/md via temp file + share | as is | download | download |
| `services/note_pdf.dart` + `printing` | PDF render/print/share | as is | `printing` works on web (print dialog / download) — verify | same |
| `services/link_preview_service.dart`, `youtube_service.dart` | fetch arbitrary pages | as is | **CORS-blocked** → `POST /api/fetch` on phone | defer: leave card `fetched=false`, enrich later (§9) |
| `Image.network` ×8 | tweet/og/YouTube images | as is | `webHtmlElementStrategy: fallback` | same |
| `services/notification_service.dart` | local notifications | as is | no-op; phone reschedules on incoming change (§10.5) | no-op; reminders inert until synced |
| `services/dnd_service.dart`, `focus_media_service.dart` | Android channels | as is | already guarded `!kIsWeb` — verify no call throws | same |
| `services/crypt_auth.dart` | `local_auth` | as is | phone-approved unlock (§2.3) | Crypt excluded (§2.3) |
| `screens/share_popup.dart`, `shareMain` | share popup engine | as is | not compiled into web entry | same |
| `SystemChrome.*` in `main.dart` and screens | status/nav bar styling | as is | skip on web | skip |
| `HapticFeedback.*` | haptics | as is | no-op on web already | same |
| `path_provider` in 8 files | temp/docs dirs | as is | not called on web | not called |

Files importing `dart:io` (all must be cleaned or confined): `dnd_service`,
`backup_service`, `focus_media_service`, `book_export`, `storage_service`,
`app_state`, `spaces_screen`, `space_detail_screen`, `markdown_note_screen`,
`root_shell`, `book_screen`, `circuit_map_screen`, `book_read_screen`,
`note_editor_screen`, `crop_screen`, `journal_screen`, `card_detail_screen`,
`settings_screen`, `thumbnail_label`, `glass`, `note_read_body`,
`note_body_editor`.

### 5.2 New files under `lib/platform/`
- `braim_image.dart` — `BraimImage(path, fit, cacheWidth, …)` and
  `braimImageProvider(path)`. Android: `FileImage`. Web: resolves via the active
  `ImageStore`. Every `Image.file`/`FileImage` call site switches to this; the
  props (`fit`, `cacheWidth`, `errorBuilder`) pass straight through.
- `image_store.dart` — `saveBytes(bytes, ext) → path`, `load(path) → bytes`,
  `delete(path)`. Android: wraps `StorageService`. Web local: IndexedDB.
  Web remote: HTTP to phone with an in-memory LRU of decoded bytes.
- `file_saver.dart` — `save(Uint8List bytes, String filename, String mime)`.
  Android: temp file + `SharePlus` (today's code, moved). Web: anchor download
  (`package:web` Blob + `URL.createObjectURL`).
- `file_open.dart` — pick a file and return `(name, bytes)`; wraps
  `file_picker` with `withData: true` on web.
- `platform_caps.dart` — see §5.3.

### 5.3 Capabilities, not `kIsWeb` checks in screens
`StoreCapabilities` / `PlatformCaps` exposes booleans the UI reads:
`canBackupToDevice`, `canScheduleReminders`, `canUseCamera`, `canShareIntent`,
`canDnd`, `canFetchPreviews` (true on Android and remote; false in local),
`cryptUnlock` (enum: biometric / phoneApproval / unavailable),
`canImportBackupZip`, `canExportBackupZip`. Screens hide or disable rows by
capability. This keeps `kIsWeb` out of ~40 screen files and makes remote vs
local differences one table.

---

## 6. Images

- **Identity = basename.** Paths are absolute device paths
  (`/data/user/0/com.solo.braim/app_flutter/images/<uuid>.jpg`). The web never
  uses the directory part: `imageKey(path) = basename(path)`. The phone resolves
  `GET /api/image/<key>` against its own images dir. Local mode stores blobs
  keyed by the same basename. So a library imported from a backup zip (whose
  `images/` entries are basenames) renders without rewriting any model field.
- **New images created on the web** get `saveBytes` → a new `<uuid>.<ext>` key;
  the path stored in the model is `images/<uuid>.<ext>` (relative). Android must
  accept relative paths too: `BraimImage` on Android resolves a relative path
  against the images dir. Add this in Phase 1 so it exists before any web write.
- **Remote upload:** `PUT /api/image/<key>` with the bytes, *before* the row
  change that references it is pushed.
- **Downscale on web too.** `image_picker` on web ignores `maxWidth/maxHeight`
  in some browsers — verify; if so, decode + resize in Dart
  (`ui.instantiateImageCodec(targetWidth:)`) before saving, matching
  `ImageService._maxContentSide = 1920` and `_maxThumbSide = 800`.
- `cacheWidth` hints keep working with `Image.memory`/network providers.
- Deleting images: `refreshAfterImageRemoval` / `deleteImage` route through
  `ImageStore.delete`. In remote mode the phone deletes only when the row that
  referenced it is gone (let the phone own image GC).

---

## 7. Settings: shared vs per-device

In remote mode the browser writes into the phone's library, so toggling dark
mode on the laptop must not flip the phone. Split `AppData` settings:

| Stays per device (web keeps its own in `localStorage`) | Shared with the library (written to the store) |
|---|---|
| `darkMode`, `darkFollowSystem` | `journalMonthCovers`, `readerPositions`, `readerBookmarks` |
| `cardsCompact`, `sortMode` | `pinnedReflexId`, `progressImpulseId`, `journalOrder` |
| `feedWallpaper`, `feedBackgroundLight/Dark` | `noteBodyFont`, `readerFont`, `readerTheme` |
| `journalPaneOpen`, `cortexPaneOpen`, `progressShowAll` | `journalReminderOn/Minutes` (phone acts on them) |
| `readerFontScale`, `tutorialSeen` | `typingMillis` (see note) |
| **never written from web:** `lastBackupAt`, `backupReminderDismissedAt`, `localAutoBackup*`, `lastLocalAutoBackupAt` | |

- Implement as a `settingsScope` map in `AppState`: on web, `push` strips
  per-device keys from the delta and `load` overlays the `localStorage` values.
  Android behaviour unchanged (everything shared = everything local).
- `typingMillis` is a counter; last-writer-wins would drop typing time from one
  side. v1: web accumulates its own and sends `+delta` via a dedicated message
  (`{"op":"addTyping","ms":…}`), phone adds. Don't overthink it.

---

## 8. Desktop adaptation (UI "as it is", input fixed for a PC)

- **`DesktopFrame`** (web only, in `MaterialApp.builder` around the existing
  `ColoredBox`): centred column `maxWidth 480`, full height, rounded 0,
  backdrop = current feed wallpaper blurred + dimmed. Override `MediaQuery`
  `size`, `padding`/`viewPadding` (zero), `devicePixelRatio` untouched.
- **Right-click = long-press.** 57 `onLongPress` sites, 0 `onSecondaryTap`.
  Add `onSecondaryTap` (or `onSecondaryTapUp` where the handler needs a
  position) alongside every `onLongPress` that opens a menu or action sheet —
  start with the shared widgets (`note_card.dart`, `space_tile.dart`,
  `tweet_card_widget.dart`, `quick_actions_menu.dart`, the hyperlink menu in
  `note_body_editor.dart`) and grep the rest. Long-presses that start a drag
  (reorder, circuit map) stay mouse-hold only. Harmless on Android (no
  secondary button). Call `BrowserContextMenu.disableContextMenu()` at web
  startup so the browser's menu never covers the app's. Mouse press-and-hold
  still triggers long-press natively.
- **Text fields keep the browser context menu** inside quill/text inputs if the
  app has none there (verify copy/paste in the note editor with mouse + Ctrl+C/V).
- **Drag with a mouse.** `_NoStretchScrollBehavior` extends
  `MaterialScrollBehavior`, whose `dragDevices` exclude the mouse. Add
  `PointerDeviceKind.mouse` for the root `PageView` (Home/Cards/… swipes) and
  the side-pane drag only, not for lists (it would fight text selection). Wheel
  and trackpad scrolling already work.
- **Keyboard.** `Shortcuts`/`Actions` at the root (web only):
  `Esc` = back (`Navigator.maybePop`), `Ctrl/Cmd+K` or `/` = universal search,
  `Ctrl/Cmd+N` = new note on the current tab, `Ctrl/Cmd+Enter` = done in
  editors, `←/→` = previous/next main tab when no text field has focus.
- **Browser Back button** must pop the top route (Navigator 1.0 is used
  everywhere, no URL routing). Verify; no deep links in v1. Use
  `usePathUrlStrategy()` only if Back misbehaves with hash URLs.
- **Hover.** `SystemMouseCursors.click` on tappable cards/tiles via the shared
  widgets; not required for v1 parity, cheap to add in Phase 6.
- **Haptics, `SystemChrome`, status-bar icon styling** — skipped on web.
- **Tab visibility.** `AppLifecycleState.paused/hidden` fires when the tab is
  hidden: keep `flushNow()`; `maybeBackupOnPause()` must no-op on web (caps).
- **Pomodoro.** `PomodoroController` computes `remaining` from `_phaseEnd -
  DateTime.now()`, so background-tab timer throttling won't drift the clock;
  the ring just redraws late. Phase-end chime needs the tab alive; no DND, no
  media notification on web.

---

## 9. Outbound fetches and remote images (CORS)

Browsers refuse cross-origin reads of arbitrary pages. On web:

- **Remote mode:** `LinkPreviewService`/`YoutubeService` call through an
  injected `Fetcher`; web-remote's `Fetcher` hits `POST /api/fetch {url}` on the
  phone, which performs the request with `package:http` and returns
  `{status, headers(content-type), body}` (cap 3 MB, 10 s timeout, http/https
  only, authenticated session only — otherwise it's an open proxy on the LAN).
- **Local mode:** `canFetchPreviews = false`. Cards saved on the web keep
  `fetched=false` and show the plain-link fallback; the existing
  `enrichAttempts < 3` loop in `_applyData` must **not** spend attempts on web
  local (it would burn all 3 on CORS failures). They get enriched when the
  library next reaches the phone.
- **Images from other sites:** set `webHtmlElementStrategy:
  WebHtmlElementStrategy.fallback` on every `Image.network` (Flutter ≥ 3.29),
  so hosts without CORS headers still render via an `<img>` element. In remote
  mode an optional `/api/proxy-image?url=` can be used instead if fallback
  rendering clips effects (e.g. blur/colour filters on top of the image).

---

## 10. Remote mode: the phone server (Android side)

### 10.1 Server
- `lib/services/phone_server/phone_server.dart` — `dart:io` `HttpServer.bind(
  InternetAddress.anyIPv4, 8787)` (fall back to port 0 if taken). Started from
  Settings → "Open on computer"; stopped by the same toggle, app exit, or 15 min
  idle with no connected browser.
- Runs inside the main app engine and talks to the phone's own `AppState`
  (holding a reference from the Provider), so the phone UI and the browser share
  one in-memory library — no second DB handle, no cross-engine races.
- Keep-alive: while the server is on, run an Android foreground service with a
  persistent notification ("Braim is open on your computer · Stop"). Type
  `dataSync` is time-capped on Android 15 — prefer `specialUse` with a Play
  declaration, or accept "works while the app is open" for v1. **(confirm)**
- Show the URL and a QR code in the sheet: `http://<wifi-or-hotspot-ip>:8787/#p=<pairing-code>`.
  Enumerate interfaces with `NetworkInterface.list()`; prefer `wlan*`/`ap*`/
  `swlan*` IPv4. Show all candidates if more than one.

### 10.2 Pairing and auth
- Pairing code: 128-bit random, single use, valid 5 min, shown only in the QR/URL
  fragment (fragments are not sent in HTTP requests or logged).
- Web reads `#p=` → `POST /api/pair {code, deviceName}` → phone shows a confirm
  dialog ("Allow Chrome on Windows to open Braim?") → returns a session token
  (256-bit). Web stores the token in `sessionStorage` (or `localStorage` if
  "remember this computer" is ticked); phone stores paired devices in settings
  with revoke in Settings.
- Every `/api/*` call and the WebSocket carry `Authorization: Bearer <token>`
  (WebSocket: first message `{"op":"auth","token":…}`, close on failure).
- Static bundle files are served without auth (they contain no data).
- Plain HTTP means LAN traffic is readable by others on the same network. On
  the phone's own hotspot that's fine. Document it in the sheet ("Use your
  hotspot or a trusted Wi-Fi"). Encryption-in-transit is a Phase-8 item
  (self-signed HTTPS or an app-level cipher keyed from the pairing code).

### 10.3 Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/`, `/main.dart.js`, `/canvaskit/*`, … | web bundle (§12.2) |
| GET | `/assets/*` | Flutter assets, streamed from the phone's `rootBundle` (don't ship them twice) |
| GET | `/api/hello` | `{"app":"braim","proto":1}` — mode detection, no auth |
| POST | `/api/pair` | pairing → token |
| GET | `/api/snapshot` | whole library as `AppSnapshot` JSON (rows + shared settings), gzip; Crypt rows withheld unless unlocked |
| WS | `/api/live` | bidirectional deltas (§10.4) |
| GET/PUT | `/api/image/<key>` | image bytes (`Cache-Control: private, max-age=31536000, immutable` — keys are UUIDs) |
| POST | `/api/search` | FTS5 search on the phone → `[{id, kind}]` |
| POST | `/api/fetch` | link-preview proxy (§9) |
| POST | `/api/crypt/unlock` | triggers biometric prompt on phone; returns crypt rows on success |

### 10.4 Live protocol (`/api/live`, JSON text frames)
- Every frame: `{"op":…, "seq":n, …}`. Newline-free JSON; WebSocket already frames
  messages (no manual length prefix needed, unlike raw TCP).
- Browser → phone: `{"op":"push","delta":{rows:[…],settings:{…}}}` from
  `RemoteLibraryStore.push` (the `SnapshotDiffer` output). Phone applies it via
  `AppState.applyIncoming`, which persists through the phone's normal
  `_persist` → SQLite path, then replies `{"op":"ack","seq":n}`.
- Phone → browser: after every phone `_flush`, the phone's differ output is also
  broadcast as `{"op":"push",…}` to connected browsers, **excluding** changes
  that originated from that browser (tag deltas with origin id).
- Ordering rule: the phone is the single writer of record. Whatever it applies
  last wins. No merges needed — two devices editing the same note in the same
  second is a user-visible race, handled by §10.6, not by a merge algorithm.
- Reconnect: on drop, the browser keeps editing into its in-memory state and
  queues pushes (they're diffs vs. the last acked baseline); on reconnect it
  re-fetches `/api/snapshot`, reapplies queued local changes on top, pushes.
  Show a small "Reconnecting to phone…" pill; after 60 s offline, make the app
  read-only with a banner (remote mode has no durable local copy).

### 10.5 Side effects that must run on the phone
When the phone applies a browser delta: reschedule notifications for changed
notes/reflex threads (`NotificationService.syncNote`,
`scheduleThreadReminder`/`cancelThreadReminder`), re-sync the journal reminder
if its settings changed, update FTS rows (already done by `DbStore` on sync).
Factor the scheduling bits of `_applyData` into a reusable
`_syncSideEffects(changedIds)` and call it from `applyIncoming`.

### 10.6 Open editors vs. incoming changes
`resume()`'s comment records why swapping note objects under an open editor is
bad. `applyIncoming` must not replace the `Note` instance an editor is holding:
- Keep an `openEditors` set of note ids (editor screens register/unregister).
- Incoming change for a note not open: replace in the list.
- For an open note: copy fields into the existing instance only if the local
  editor has no unsaved changes; otherwise keep local and show a one-line
  banner in the editor: "Changed on your phone · Load" (Load discards local).
Same rule on the phone side for edits arriving from the browser.

---

## 11. Local mode: the browser keeps its own copy

### 11.1 Storage
- `sqflite_common_ffi_web`: set `databaseFactory = databaseFactoryFfiWeb` and
  run its setup (`dart run sqflite_common_ffi_web:setup`) to copy
  `sqlite3.wasm` + `sqflite_sw.js` into `web/`. Reuse `DbStore`/`BraimDatabase`
  unchanged; `BraimDatabase._ensureFts` already falls back if FTS5 is missing
  in that WASM build (verify which).
- No legacy JSON import on web: `WebLocalLibraryStore.init` opens the DB
  directly; `DbMigrator` must be skipped or told "no legacy store".
- Images: IndexedDB object store `images` keyed by basename (§6). Use
  `package:web` + `js_interop` directly; a small wrapper, no extra dependency.
- Call `navigator.storage.persist()` on first write and show a warning in
  Settings if it's denied (the browser may evict the library under storage
  pressure; Safari evicts non-installed sites after 7 days unused).

### 11.2 Import from phone
- Settings → "Import backup from phone": pick the existing backup `.zip`
  (`BackupService` format: `data.json` + `images/*`). Parse with `archive` in
  memory, write rows via `DbStore.syncFromAppData(AppData.fromJson(...))`, put
  images in IndexedDB, then `AppState.init()` again.
- Crypt rows filtered out on import (§2.3).
- Refuse to import over a non-empty library without an explicit "Replace
  everything on this computer" confirm.

### 11.3 Export
- "Export backup (.zip)" produces the same format the phone restores
  (`data.json` + `images/`), so a browser-only library can move to the phone
  with the existing restore flow. This is the manual Option 3 path and it's
  free.

### 11.4 Door left open for Option 2 sync (do not build now)
- Keep row-level deltas the unit of change (they are, via `SnapshotDiffer`).
- Hard deletes are invisible to a peer that wasn't connected. When sync is
  built it will need tombstone rows; nothing in this plan may assume a missing
  row means "never existed".
- Don't add fields to the wire format that assume a single writer beyond the
  `origin` tag.

---

## 12. Web build configuration

### 12.1 Project
- `flutter create --platforms web .` — adds `web/` (index.html, manifest,
  icons). Replace icons with the Braim logo (`assets/logo_icon.png`), set
  `theme_color`/`background_color` to the app surface colour, title "Braim".
- A splash in `index.html` matching the app's loading state so the CanvasKit
  download doesn't show a white page.
- Entry point stays `lib/main.dart`; mobile-only initialisation branches on
  `kIsWeb` there.

### 12.2 Build flags
```
flutter build web --release --no-web-resources-cdn --pwa-strategy=offline-first
```
- `--no-web-resources-cdn` is mandatory: by default CanvasKit is fetched from
  Google's CDN, which fails off-grid.
- **Fallback fonts:** Flutter web downloads Noto fallback fonts (emoji,
  Devanagari, CJK) from Google on demand. Off-grid that fails and glyphs render
  as boxes. Verify behaviour with the network blocked; if boxes appear, bundle
  Noto Color Emoji + Noto Sans Devanagari as assets and add them to
  `fontFamilyFallback` in the theme (web only, size cost ~10 MB — measure).
- Phone-served bundle: `--pwa-strategy=none` (no service worker in an insecure
  context anyway); `--base-href /`.

### 12.3 Shipping the bundle inside the APK (remote mode)
- The web build must not end up inside its own Flutter assets. Put it in
  Android native assets: `android/app/src/main/assets/web/` (generated, git-
  ignored), read by a tiny `braim/webbundle` MethodChannel (`AssetManager.open`)
  that `PhoneServer` calls per file, cached in memory after first read.
- Strip `build/web/assets/` from the copy — `/assets/*` is served from the
  phone's `rootBundle` (saves ~21 MB of duplicated wallpapers/fonts).
- Measure APK growth (CanvasKit wasm + `main.dart.js`); expect several MB
  compressed. Record it in the phase checklist.
- `tool/build_web_bundle.sh`: `flutter build web …` → prune assets → copy into
  `android/app/src/main/assets/web/` → then the usual `flutter build appbundle`.
  The AAB build must run this first; document in README.

---

## 13. Phases

### Phase 0 — Toolchain and a web target that compiles
- [ ] Install Flutter (stable with Dart ≥ 3.11.5, per `pubspec.yaml`) in the
      container; `flutter doctor`; `flutter test` green on untouched code.
- [ ] `flutter create --platforms web .`; commit `web/`.
- [ ] Make `flutter build web` compile: introduce `lib/platform/` stubs and
      conditional imports until there are zero `dart:io` imports outside
      allowed files. No behaviour change on Android.
- [ ] Android: `flutter test`, `flutter build apk --debug` green.

### Phase 1 — Seams (Android behaviour unchanged)
- [ ] Extract `SnapshotDiffer` from `DbStore`; `db_store_test.dart` green unchanged; new differ tests.
- [ ] `LibraryStore` + `DeviceLibraryStore`; `AppState(store:)`; move init/flush/flushNow store logic into it.
- [ ] `AppState.applyIncoming(delta)` + tests (insert, replace, hard delete, settings, no echo).
- [ ] `BraimImage` / `ImageStore` / `FileSaver` / `FileOpen` / caps; replace all 13 `Image.file`/`FileImage`, all export/share call sites, `_importFile`, crop.
- [ ] Relative image paths resolve on Android.
- [ ] `Fetcher` injection for link previews / YouTube.
- [ ] Settings scope split (§7), no-op on Android.
- [ ] Regression: install debug APK on device over an existing library; everything opens, edits persist across restart, backup/restore still works.

### Phase 2 — Local mode MVP (browser only, no phone needed)
- [ ] `WebLocalLibraryStore` on sqflite web; images in IndexedDB.
- [ ] Empty-library screen with "Import backup from phone"; import zip (§11.2).
- [ ] All screens render the imported library; screenshots at 1440×900 vs phone screenshots match (§14.3).
- [ ] Create/edit/delete notes, cards, spaces, books, journal entries, reflexes; reload the tab; changes persist.
- [ ] Export zip; restore it on the phone with the existing flow; data identical.
- [ ] Caps hide: device backups, notifications, camera, share intent, DND; link previews deferred.

### Phase 3 — Desktop frame and input
- [ ] `DesktopFrame` (§8) with wallpaper backdrop; light/dark follows `prefers-color-scheme` when "follow system" is on.
- [ ] Right-click = long-press everywhere a long-press exists; browser context menu disabled.
- [ ] Mouse drag on main PageView + side pane; wheel/trackpad scroll everywhere.
- [ ] Keyboard shortcuts; browser Back pops routes.
- [ ] Editor: typing, selection, copy/paste, link insert/edit menu (the hyperlink feature), wiki-link `[[` picker, `@@@` mentions all work with keyboard + mouse.

### Phase 4 — Phone server, read-only remote mode
- [ ] `PhoneServer` + Settings "Open on computer" sheet with QR + URL.
- [ ] Bundle build script; bundle served from the APK; `/assets/*` from `rootBundle`.
- [ ] `/api/hello`, pairing + confirm dialog + token, `/api/snapshot`, `/api/image`.
- [ ] Web detects remote mode, pairs, renders the phone's library. Crypt withheld.
- [ ] Works on home Wi-Fi and with the laptop on the phone's hotspot, with mobile data **off** and the laptop's Wi-Fi otherwise disconnected from the internet.

### Phase 5 — Remote writes and live updates
- [ ] `/api/live` both directions; `RemoteLibraryStore.push` sends differ output; acks.
- [ ] Phone edits appear in the browser within ~1 s and vice versa.
- [ ] Side effects run on the phone for browser edits (reminders scheduled, FTS updated).
- [ ] Open-editor rule (§10.6) on both sides.
- [ ] Image upload before row push; new web images visible on the phone.
- [ ] `/api/fetch` proxy: a link card saved on the web gets its preview.
- [ ] `/api/search` used for search in remote mode.
- [ ] Crypt unlock via phone biometric; auto re-lock on idle.
- [ ] Disconnect/reconnect behaviour (§10.4); read-only after 60 s offline.
- [ ] Foreground service keeps the server alive with the phone screen off (or documented limitation).

### Phase 6 — Polish
- [ ] Hover cursors, tooltips on icon buttons.
- [ ] Drag-and-drop images/links/markdown files onto the window (web) → same path as share intent.
- [ ] PWA install for local mode (secure-context host, §2.2).
- [ ] Paired-devices list with revoke; server auto-stop.
- [ ] Offline fonts verified (§12.2).
- [ ] Try `--wasm`; keep if it passes §14 and is faster.

### Phase 7 — (optional) wide layout
Only if Kalpesh asks after living with the phone column: two-pane editor/list,
multi-column masonry feed, reader with side TOC. Built as breakpoints inside the
existing screens, not new screens.

### Phase 8 — (later, separate plan) Option 2 sync and transport encryption
HLC per row, tombstones, conflict copies, WebRTC or phone-server merge,
encrypted transport. Not part of this plan.

---

## 14. Verification

### 14.1 Toolchain in the cloud container
No Flutter SDK is installed there. Install stable Flutter under `/opt/flutter`
(or the user's home), add to `PATH`, `flutter config --enable-web`,
`flutter precache --web`. Chromium is at `/opt/pw-browsers/chromium`
(Playwright available) — use it for web runs; do not run `playwright install`.

### 14.2 Automated
- `flutter test` (all existing tests stay green; new tests for differ,
  `applyIncoming`, settings split, image key resolution, zip import/export on
  in-memory stores).
- `flutter analyze` clean.
- `flutter build web --release --no-web-resources-cdn` and
  `flutter build apk --debug` both succeed in CI-like conditions.
- A Playwright script (`tool/web_smoke.mjs`) that serves `build/web`, loads it
  with a fixture backup (`test_data/`), and screenshots every main tab + key
  screens at 1440×900, light and dark.

### 14.3 Parity checklist (compare against phone screenshots)
Home feed (pinned, tags, greeting, wallpaper) · Cards (Open + Blocks) · Spaces +
space detail · Note editor (text, images, links, checklists, code, tags,
reminder field) · Markdown note · Circuit map (both layouts, collapse, share) ·
Books list, book screen, reader (fonts, themes, positions, bookmarks), chapter
history, find/replace · Journal (week strip, entries, month covers) + year view
· Reflexes, daily day, impulse history + analytics · Pomodoro · Universal
search · Archive · Recently deleted (restore groups) · Settings (only rows the
caps allow) · Side pane · Tutorial on first run.

### 14.4 Off-grid test (remote mode)
Phone: mobile data off, hotspot on. Laptop: joins the hotspot, no other
network. Load the URL, pair, browse, edit on both sides, add an image on each
side, disconnect Wi-Fi for 30 s and reconnect. Nothing requests an internet
host (check DevTools Network for any non-LAN request).

---

## 15. Risks and unknowns (verify, don't assume)

| Risk | Why it matters | Check in |
|---|---|---|
| Glass/`BackdropFilter` performance under CanvasKit | The UI leans on blur everywhere (`glass*`, `frosted_*`, `island_nav`, `quick_actions_menu`); low-end laptop GPUs may stutter | Phase 2 — profile; `--wasm`; reduce blur sigma on web if needed |
| Every plugin actually works on web | `printing`, `image_picker`, `file_picker`, `flutter_timezone`, `palette_generator`, `crop_your_image`, `flutter_quill` claim web support; details differ (e.g. picker downscaling) | Phase 0/2 |
| FTS5 in the sqflite web WASM build | Search quality in local mode | Phase 2 (in-memory fallback exists) |
| Offline fallback fonts | Emoji / Hindi render as boxes off-grid | Phase 4/6 |
| Android 15 foreground-service limits | Server killed with screen off | Phase 5 |
| APK size growth from the embedded web bundle | Play download size | Phase 4 — measure, record |
| Browser storage eviction (local mode) | Silent data loss if the browser is the only copy | Phase 2 — `storage.persist()`, export reminder |
| `AppState` monolith assumptions (e.g. code holding `Note` references across awaits) | `applyIncoming` replacing instances could break flows beyond editors | Phase 5 — grep for long-lived `Note` references in screens |
| Browser Back with Navigator 1.0 | Back button leaves the app instead of popping | Phase 3 |
| Plain-HTTP LAN traffic | Readable on shared Wi-Fi | Documented; Phase 8 fixes |
