# Braim Web: Build Guide

A build reference for **Braim Web**: the phone runs a small web server inside
the Braim app, and a laptop on the same network opens the library in an
ordinary browser. Written so an AI coding agent or a developer can build the
whole feature from this file alone, without the conversation that produced it.

Companion docs: `docs/circuit-feature-plan.md` (Circuits),
`docs/sqlite-migration-plan.md` (storage), `README.md` (the operator's
handbook), `PRIVACY.md`.

---

## 0. How to use this guide

- Work phase by phase (section 13). Do not start a phase until the previous
  phase's checklist is ticked, `flutter analyze --no-pub` is clean and
  `flutter test --no-pub` is green.
- Tick the checkboxes in this file as you go, so a later session can resume.
- Phase 1 is pure Dart with no phone UI. Build it test-first.
- At the end of every phase with something visible, install on the emulator
  and hand the owner a numbered test script (section 14). Do not drive the
  emulator yourself.
- Read sections 5, 11 and 15 (security, concurrency, pitfalls) before writing
  any code. They cover the ways this feature can leak data or lose edits.
- When something is not decided here, choose the smallest behaviour that loses
  no data and exposes nothing, add it to section 17, and ask the owner.

---

## 1. The feature

Decided with the owner on 2026-09-30.

- **The phone is the server.** Braim keeps a single copy of the library, on the
  phone. The laptop never stores it. This is how the original WhatsApp Web
  worked, minus WhatsApp's relay servers: Braim Web is local-only.
- **Not screen streaming.** The laptop gets real web pages built from the
  library, not a video of the phone screen.
- **A website, not an app.** Plain pages, small scripts only where needed, no
  framework and no build step. No install on the laptop. It must feel light.
- **Same network only**, for this version. The laptop must be on the same
  Wi-Fi as the phone, or connected to the phone's hotspot. Access from anywhere
  is a later project (section 18).
- **Plain HTTP**, not HTTPS. Owner's condition: only if it causes no Google
  Play problem. It doesn't (section 16).
- **Pairing with a 6-digit code.** The phone shows a code; the user types it
  into the laptop's browser. No camera, no QR. The owner accepted QR only as a
  fallback if the code caused problems; it doesn't, so QR is out.
- **Scope of this version:** notes (rich and Markdown), Sparks, Circuits and
  Books. Everything else stays phone-only (section 18).
- **Off by default.** The user turns Braim Web on in Settings, and it turns
  itself off after a period with no activity.

---

## 2. Ground rules (must follow)

- **Scope.** The working tree may hold the owner's unrelated uncommitted work.
  Never revert, reformat or restage files you did not change for this feature.
  Commit only when the owner asks, stage only Braim Web files, follow the
  repository's commit-identity instructions, and never add a
  `Co-Authored-By` trailer.
- **One source of truth.** Every read and write goes through `AppState`. The
  server never touches SQLite, `keepy_data.json` or `StorageService.save`
  directly. Mutate the live objects in AppState's lists, then call the existing
  AppState method (`upsertNote`, `updateCard`, the circuit and book methods).
  That keeps the phone screen, the SQLite store and backups consistent.
- **Live instances only.** Never copy a `Note`, `TweetCard` or `Book` to edit
  it. Look it up (`noteById`, `cardById`, `bookById`) and mutate that instance,
  because an open phone screen may be holding the same object.
- **No data-format changes.** No new `Note` fields, no SQLite schema change, no
  change to the backup format. Everything the web edits already exists in the
  models. Braim Web's own state (sessions) lives in a separate file that is
  **not** part of backups (section 5.4).
- **The Crypt never reaches the web.** Not in lists, pages, search, links,
  circuit maps or images. Section 5.6.
- **Everything is escaped.** Card text, article text and link titles come from
  websites. Every string that reaches HTML goes through an escaper or the
  sanitizer (section 5.5).
- **Phone chrome.** New phone screens use `FrostedScaffold` and
  `FrostedCircleButton` (`lib/widgets/frosted_chrome.dart`).
- **Type.** Bundled fonts stop at weight 700. Never use `FontWeight.w800` or
  `w900` in Flutter, or `font-weight` above 700 in the web CSS.
- **Strings.** Every user-visible string, on the phone and on the web, goes in
  `lib/l10n/app_en.arb`; run `flutter gen-l10n`. The server reads them with
  `lookupAppLocalizations(const Locale('en'))`.
- **Docs voice.** The README is an operator's handbook with numbered sections
  and no em dashes. Match it.
- **Known dead end.** Android predictive-back peek cannot work in this app.
  Do not investigate it.

---

## 3. Architecture

```
Laptop browser                         Phone (Braim app process)
--------------                         ------------------------------------------
 GET /notes/abc  ─── Wi-Fi / hotspot ──▶ BraimWebServer (Dart, shelf, main isolate)
                                          │  host + address checks
                                          │  session + CSRF checks
                                          │  route handler
                                          ▼
                                        AppState  ◀── the same object the phone UI uses
                                          │
                                          ▼
                                        SQLite store, images folder (unchanged)

 EventSource /api/events ◀── "changed" events, throttled, from AppState.notifyListeners
```

- **Server in the app's Dart code.** `BraimWebServer` runs in the main isolate
  next to `AppState`, so a web edit calls the same methods a phone tap does.
- **A foreground service keeps the process alive.** An Android service with a
  persistent "Braim Web is on" notification stops Android from freezing or
  killing Braim while the phone screen is off. The service holds no data and
  runs no server; it only keeps the process alive.
  *Update, 3 Oct 2026 (versionCode 17):* the service was removed, because
  its `FOREGROUND_SERVICE_CONNECTED_DEVICE` permission needs a Play Console
  declaration that slows review. Braim Web now keeps the screen on instead
  (`FLAG_KEEP_SCREEN_ON` through the `braim/screen` channel), so it works
  while Braim is open on the phone. The service sections below describe the
  earlier design; to bring it back, revert the commit that removed it.
- **Pages are built on the phone.** The phone renders HTML. The laptop receives
  finished pages plus a few small scripts. This reuses Braim's existing Dart
  code: the rich-text line parser, the Markdown package, the circuit layout
  engine and the full-text search index.
- **Editing uses Quill.** Braim's rich notes are stored in Quill's Delta format
  (`flutter_quill` is a port of Quill). The web editor is Quill itself, so
  notes round-trip without losing formatting. It loads only on edit pages.

---

## 4. Codebase map (read before Phase 1)

| Area | File | Why it matters |
|---|---|---|
| All state | `lib/state/app_state.dart` | Every read and write. `revision`, `notes`, `searchableNotes`, `searchableCards`, `cards`, `noteById`, `cardById`, `upsertNote`, `addMarkdownNode`, `deleteNote`, `createLinkedNote`, `resolveLink`, `searchIndex`, `addCardFromUrl`, `updateCard`, `deleteCard`, `books`, `bookById`, `bookPages`, `addBookChapter`, `reorderBookPages`, `updateBook`, the circuit API (`circuitNodes`, `circuitChildren`, `circuitPath`, `newCircuitRootDraft`, `ensureCircuitRootSaved`, `addCircuitChild`, `addCircuitSibling`, `moveCircuitNode`, `renameCircuitNode`, `setCircuitLayout`, `deleteCircuitSubtree`, `deleteCircuitNodeKeepSlot`, `deleteCircuit`, `writeIntoPlaceholder`, `deletePlaceholder`), visibility predicates `_isLiveNote`, `_isFeedNote`, `_isSearchableNote`, `_hiddenFoldIds` |
| App entry | `lib/main.dart` | `ChangeNotifierProvider(create: (_) => AppState()..init())`. Add the web controller here |
| Note model | `lib/models/note.dart` | `blocks`, `title`, `markdown`, `markdownSource`, `updatedAt`, circuit fields, `richToStyledLines`, `richToLines`, `richToPlain`, `toggleChecklistLine`, `RichLine`, `RichRun` |
| Blocks | `lib/models/note_block.dart` | `NoteBlockType { text, image, link }`; text blocks hold a Delta JSON string or legacy plain text |
| Sparks | `lib/models/tweet_card.dart` | `url`, `text`, `noteTitle`, `authorName`, `authorHandle`, `siteName`, `coverImageUrl`, `articleText`, `videoDescription`, `videoTranscript`, `blocks`, `updatedAt` |
| Books | `lib/models/book.dart` | `Book` fields; `BookPageKind` (`contents`, `intro`, `chapter`, matter kinds, `note`), `isQuietMatter` |
| Markdown | `lib/services/note_markdown.dart` | `markdownTitle`, `markdownPlainPreview` |
| Wiki-links | `lib/services/wiki_links.dart` | `wikiLinkPattern`, `splitWikiSpans`, `LinkRef`, `LinkKind` |
| Circuit layout | `lib/services/circuit_layout.dart` | `layoutCircuit`, `CircuitLayout` (`rects`, `edges`, `canvasSize`, `plusAnchor`) |
| Circuit map | `lib/screens/circuit_map_screen.dart` | `_layoutFor` shows how to build the `children` map; `_EdgePainter` shows the edge shapes to mirror in SVG; `_NodeChip` shows node styling |
| Search UI | `lib/widgets/universal_search.dart` | The index-plus-substring merge to extract and share (Phase 3) |
| Phone editors | `lib/screens/note_editor_screen.dart`, `markdown_note_screen.dart`, `card_detail_screen.dart` | `_startEditing`, `_finishEditing` / `_done`, `_close` / `_leave`, `dispose`: where edit leases are taken and released (section 11) |
| Images | `lib/services/storage_service.dart` | `imagesDir`; note images and book covers live there with UUID file names |
| Settings | `lib/screens/settings_screen.dart` | Add the Braim Web section, between Backup and Storage |
| Android | `android/app/src/main/kotlin/com/solo/braim/MainActivity.kt`, `AndroidManifest.xml` | Method-channel pattern (`braim/dnd`, `braim/media`); add `braim/web` and the service |
| Resource pins | `android/app/src/main/res/raw/keep.xml` | Names looked up at runtime; add any new ones |
| Test harness | `test/app_state_test.dart` | `_FakePathProvider`, `newState`, `boot`, teardown flush. Copy this pattern |

---

## 5. Network and security

The threat model: other devices and people on the same Wi-Fi, and malicious
websites open in the laptop's browser. Plain HTTP means traffic on a shared
network can be read; the design accepts that (owner's decision) and says so in
the UI. Everything else below is required.

### 5.1 Listening

- Bind to `InternetAddress.anyIPv4` on port **8420**. If it is taken, try 8421
  to 8429 and show whichever port was used.
- Reject any connection whose remote address is not private or loopback:
  `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8`. Answer 403.
  This blocks the mobile-data interface. shelf exposes the remote address as
  `request.context['shelf.io.connection_info'] as HttpConnectionInfo`.
- Addresses to show: `NetworkInterface.list(type: InternetAddressType.IPv4)`,
  keeping private addresses only. Show every one, since Wi-Fi and hotspot
  interfaces can both be present. Always display the full `http://` form,
  because some browsers try HTTPS first when the scheme is left out.
- Turn on compression: `shelf_io.serve` returns the `HttpServer`; set
  `autoCompress = true`.

### 5.2 Host check (DNS-rebinding defence)

Reject every request whose `Host` header is not one of:

- each current private IPv4 of the phone with the port, for example
  `192.168.1.23:8420`;
- `localhost:<port>` and `127.0.0.1:<port>`, needed for emulator testing
  through `adb forward` (section 14).

Answer 421. Recompute the list whenever interfaces change (check on each start
and every 30 seconds while running). Without this check, a malicious site can
rebind its own domain to the phone's address and read the library.

### 5.3 Pairing

- While Braim Web is on, the phone's Settings shows a **6-digit code** from
  `Random.secure()`, zero-padded, with a countdown.
- A code expires after **2 minutes** and after one successful use; a new one is
  shown immediately.
- After **5 wrong attempts** against the current code, the code is replaced and
  every pairing attempt is refused for **30 seconds**. Compare codes in
  constant time.
- The code is shown only in Settings, never in the notification, since
  notifications can show on the lock screen.
- Successful pairing creates a session (5.4) and redirects to `/`.
- At most **5** linked browsers. Pairing a sixth shows "Too many linked
  browsers. Log one out on your phone."

### 5.4 Sessions

- A session token is 32 random bytes, base64url. The browser holds it in the
  cookie `braim_session`: `HttpOnly`, `SameSite=Strict`, `Path=/`,
  `Max-Age` 30 days. Not `Secure`, since the site is HTTP.
- The phone stores only `sha256(token)` (add `crypto` as a direct dependency;
  it is already in the lock file transitively), with a label built from the
  browser's user agent, the creation time and the last-seen time.
- Persist sessions in `braim_web_sessions.json` in the app's documents folder.
  This file is **not** in backups: `BackupService` zips only `data.json` and
  `images/`. Keep it that way.
- A session unused for 30 days is dropped. Settings lists sessions with
  **Log out** per row and **Log out all**. The web header has **Log out**.
- Cookies belong to one address. If the phone's address changes, the browser
  must pair again. Say so on the pairing page.

### 5.5 Request hardening

- **CSRF.** Every page embeds a per-session token in
  `<meta name="braim-csrf">`. Every mutating request (`POST`, `PUT`,
  `DELETE`) must send it in `X-Braim-CSRF`; otherwise 403. Never send CORS
  headers, so other sites cannot read responses or send that header.
- **Content-Security-Policy** on every HTML response:
  `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';
  img-src 'self' https: data:; font-src 'self'; connect-src 'self';
  object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`.
  No inline scripts and no `on*` attributes anywhere in rendered HTML.
  `https:` images are allowed because Spark covers are remote.
- Also send `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`
  and `Cache-Control: no-store` on HTML and API responses.
- **Escaping.** Build HTML with Dart string functions and one escaper,
  `const HtmlEscape().convert(s)`, for text and attribute values. No template
  library.
- **Markdown sanitising.** Render with the `markdown` package
  (GitHub-flavoured), then sanitise the result with the existing `html`
  package (`parseFragment`) against an allowlist:
  - tags: `p br hr h1-h6 strong em del s code pre blockquote ul ol li table
    thead tbody tr th td a img span input` (only `type=checkbox disabled`);
  - attributes: `href` on `a`, `src` and `alt` on `img`, `class` from a fixed
    list, `checked` and `disabled` on checkbox inputs;
  - URLs: `http:`, `https:`, `mailto:` and app-relative paths only. Anything
    else, including `javascript:` and `data:` links, is dropped.
  Everything else is removed; its text is kept, escaped.
- **Links out.** External links get `rel="noopener noreferrer"` and
  `target="_blank"`.
- **Request size.** Reject bodies over 2 MB.

### 5.6 Visibility rules (Crypt and friends)

Add to AppState, next to the existing predicates:

```dart
/// A note the web may show: a live, searchable note (not deleted, not in the
/// Crypt, not archived, not a journal entry, not a circuit placeholder), or a
/// manuscript page of a live book.
bool isWebVisibleNote(Note n);

/// The Home feed for the web: like [notes] but WITHOUT the phone's transient
/// tag filter, which is phone-only view state.
List<Note> get webFeedNotes;

/// Image file names the web may serve: images in web-visible notes and cards,
/// and covers of live books. Memoized on [revision].
Set<String> get webImageNames;
```

- Every route that takes an id resolves it, then checks `isWebVisibleNote` (or
  the card or book equivalent). A failed check answers **404**, never 403, so
  hidden items are indistinguishable from missing ones.
- Card pages use the Sparks feed rules (`searchableCards` membership).
- Circuit maps require a web-visible first note; placeholders render on the
  map but are not openable as notes.
- `/img/<name>` serves a file only if `name` matches `^[A-Za-z0-9._-]+$`, is in
  `webImageNames` and exists in `imagesDir`. This keeps Crypt images private
  even if someone knows a file name, and blocks path traversal.

---

## 6. Phone side

### 6.1 Controller

`lib/web/web_controller.dart`: a `ChangeNotifier` provided in `main.dart` next
to AppState (switch to `MultiProvider`).

```dart
class BraimWebController extends ChangeNotifier {
  BraimWebController(this.state);
  final AppState state;

  bool get running;
  int? get port;
  List<String> get addresses;        // full URLs, e.g. http://192.168.1.23:8420
  String? get pairingCode;           // null when off
  Duration get codeTimeLeft;
  List<WebSessionInfo> get sessions; // label, created, last seen
  bool get anyBrowserConnected;      // an event stream is open

  Future<void> start();              // server, service, first code
  Future<void> stop({String? reason});
  Future<void> logOut(String sessionId);
  Future<void> logOutAll();
}
```

- `start()` starts the server first, then the foreground service. If the
  server fails to bind, it shows an error and starts nothing.
- `stop()` stops the server, closes every event stream and stops the service.
- **Auto-off.** Stop after **30 minutes** with no requests from any session.
  Event-stream keep-alives do not count; the page's visibility pings do
  (section 8.4), so a tab someone is looking at keeps Braim Web on.
- The controller persists nothing about "on" or "off". Braim Web is always off
  after the app restarts.

### 6.2 Foreground service (Android)

`android/app/src/main/kotlin/com/solo/braim/BraimWebService.kt`:

- A `Service` started from Dart through a new method channel `braim/web`
  (methods `start(url)`, `stop()`), registered in `MainActivity` the way
  `braim/media` is.
- Calls `ServiceCompat.startForeground(...)` with type
  `ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE`.
- Notification channel `braim_web`, low importance, silent. Title "Braim Web
  is on", text the address, small icon `ic_stat_braim`. Tapping opens the app.
  One action, **Turn off**.
- **Turn off** sends the service an intent; the service calls a static
  listener set by `MainActivity`, which invokes `stopRequested` on the
  `braim/web` channel. Dart runs `controller.stop()`, which stops the service.
  If the listener is missing, the service stops itself.
- Manifest:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE"/>

<service
    android:name=".BraimWebService"
    android:exported="false"
    android:foregroundServiceType="connectedDevice"
    android:stopWithTask="true" />
```

- `CHANGE_WIFI_STATE` is a normal permission with no prompt. It is listed
  because `connectedDevice` requires one of a set of permissions; confirm the
  current list in the Android foreground-service documentation when
  implementing.
- `stopWithTask="true"`: swiping Braim away from Recents destroys the Dart
  side, so the service must stop too, or the notification would claim a server
  that no longer exists.
- Start the service only from Settings while the app is open. Android forbids
  starting foreground services from the background.
- **Screen-off behaviour** must be verified on a real phone (section 14): leave
  the phone idle for 20 minutes with the screen off, then use the site. If
  requests stall, add a Wi-Fi lock using the mode the current Android
  documentation recommends, and note the battery cost in this file.

### 6.3 Settings section

A new "Braim Web" section in `settings_screen.dart`, between Backup and
Storage:

- **Off:** a switch, "Open Braim on your computer", and one line: "Works on
  the same Wi-Fi, or when your computer joins this phone's hotspot."
- **On:**
  - the address, large and selectable, with a copy button; more than one
    address is listed one per line;
  - the 6-digit code in large digits, grouped `482 913`, with the countdown;
  - "Linked browsers": label and last seen, **Log out** per row,
    **Log out all**;
  - a note: "Your notes stay on this phone. Anyone on this Wi-Fi could read
    the traffic, so use it on networks you trust.";
  - the switch to turn it off.
- If no private address exists (no Wi-Fi and no hotspot), the switch shows
  "Connect to Wi-Fi or turn on your hotspot first" and does not start.

---

## 7. Server design

### 7.1 Files

| File | Contents |
|---|---|
| `lib/web/web_server.dart` | `BraimWebServer`: bind, pipeline, router, start/stop |
| `lib/web/web_security.dart` | Address check, host check, session and CSRF middleware, security headers |
| `lib/web/web_auth.dart` | Pairing codes, attempt limits, session store and its file |
| `lib/web/web_events.dart` | Event-stream hub fed by AppState |
| `lib/web/web_assets.dart` | `WebAssets`: `assets/web/` files and bundled fonts, loaded from the bundle, cached, versioned |
| `lib/web/web_html.dart` | `esc`, page layout, Delta to HTML, Markdown to safe HTML, wiki-link spans |
| `lib/web/web_pages.dart` | Page builders: pair, feed, note, spark, search, circuit map, books |
| `lib/web/web_api.dart` | JSON handlers: notes, sparks, circuits, books, leases |
| `lib/web/web_controller.dart` | Section 6.1 |
| `assets/web/` | `app.css`, `app.js`, `editor.js`, `map.js`, `vendor/quill.js`, `vendor/quill.core.css`, `vendor/LICENSE-quill.txt`, `vendor/VERSIONS` |

Dependencies to add: `shelf`, `shelf_router`, and `crypto` as direct
dependencies. List `assets/web/` and `assets/web/vendor/` under `flutter:
assets:` in `pubspec.yaml`; subfolders are not included by `assets/`.

### 7.2 Pipeline order

1. Address check (5.1), then host check (5.2).
2. Static assets: `/assets/*` and `/fonts/*` need no session, so the pairing
   page can load its CSS.
3. Pairing: `GET /pair`, `POST /api/pair` need no session.
4. Session check. No valid session: pages redirect to `/pair`, API calls get
   401.
5. CSRF check on mutating requests.
6. Router.
7. Security headers on every response; errors become a plain error page or
   `{"error": "..."}`, never a stack trace.

Mark the session as seen and reset the auto-off timer on every request that
passes step 4, except event-stream keep-alives.

### 7.3 Routes

Pages (HTML):

| Route | Page |
|---|---|
| `GET /pair` | Pairing form |
| `GET /` | Notes feed |
| `GET /notes/new?kind=rich\|markdown` | New note editor |
| `GET /notes/<id>` | Note view |
| `GET /notes/<id>/edit` | Note editor |
| `GET /sparks`, `/sparks/<id>`, `/sparks/<id>/edit` | Sparks list, view, editor |
| `GET /circuits`, `/circuits/<rootId>?focus=<id>` | Circuits list, map |
| `GET /books`, `/books/<id>`, `/books/<id>/read` | Books list, contents, reader |
| `GET /books/<id>/pages/<pageId>/edit` | Page editor |
| `GET /search?q=` | Search results |
| `GET /link?to=<title>` | Resolve a wiki-link, redirect to the item or show "Not on Braim Web" |

API (JSON; mutations need the CSRF header):

| Route | Action |
|---|---|
| `POST /api/pair` | `{code}`; sets the cookie |
| `POST /api/logout` | Ends this session |
| `GET /api/events` | Event stream (8.4) |
| `POST /api/ping` | Visibility ping |
| `POST /api/notes` | Create: `{kind, title, blocks}` or `{kind: "markdown", source}` |
| `PUT /api/notes/<id>` | Save (9.1); needs the lease |
| `DELETE /api/notes/<id>` | Soft delete; plain notes only, circuit notes go through 9.3 |
| `POST /api/notes/<id>/check` | `{block, line, baseUpdatedAt}`: tick a checklist line |
| `POST /api/notes/<id>/lease`, `DELETE ...` | Take or renew, release (11) |
| `POST /api/notes/<id>/images`, `DELETE .../images/<blockId>` | Add a photo (the body is the file), remove one (added Phase 8) |
| `GET /api/notes/<id>/meta` | `{updatedAt, leaseHolder}` |
| `POST /api/markdown/preview` | `{source}` returns sanitised HTML |
| `POST /api/sparks`, `PUT /api/sparks/<id>`, `DELETE ...` | Add from URL, save, soft delete |
| `POST /api/sparks/<id>/lease`, `DELETE ...` | As for notes |
| `POST /api/circuits` | `{title}`: new circuit |
| `POST /api/circuits/nodes/<id>/child`, `.../sibling` | `{markdown}`: add a titled note |
| `POST /api/circuits/nodes/<id>/rename`, `.../move` | `{title}`, `{delta: -1\|1}` |
| `POST /api/circuits/nodes/<id>/delete` | `{mode: "all"\|"keepSlot"}` |
| `POST /api/circuits/nodes/<id>/write-placeholder`, `.../remove-placeholder` | Placeholder actions |
| `POST /api/circuits/<rootId>/layout` | `{mode: "ltr"\|"ttb"\|"radial"}` |
| `GET /api/circuits/nodes/<id>/menu` | A node's menu and its dialog texts (added Phase 5) |
| `POST /api/books/<id>/chapters` | Add a chapter |
| `POST /api/books/<id>/pages/<pageId>/move` | `{delta: -1\|1}` |

Answer 404 for anything not web-visible (5.6), 409 for conflicts and held
leases (11), 400 for malformed input.

### 7.4 Performance

- Handlers run on the phone's UI isolate. Keep them light: no synchronous
  file reads, and cache rendered note HTML keyed by `(id, updatedAt)`.
- Stream images with `File.openRead()` and send
  `Cache-Control: private, max-age=31536000, immutable`; image names are UUIDs
  and never change content.
- Static assets are loaded from the Flutter bundle with `rootBundle.load`,
  cached in memory, and served with a version query string and a long
  `max-age`.

---

## 8. The web client

### 8.1 Size budget

| Piece | Budget | Loaded on |
|---|---|---|
| A page's HTML | Few KB | Every page |
| `app.css` | 15 KB | Every page |
| `app.js` | 15 KB | Every page |
| `map.js` | 8 KB | Circuit maps |
| `editor.js` | 10 KB | Edit pages |
| Quill | Roughly 200 KB, about 50 KB compressed | Edit pages only |
| Fonts | Lora plus the user's note font, 50 to 120 KB each | Cached after the first load |

No framework, no bundler and no build step. Scripts load with `defer`. Record
the actual sizes in this file at the end of Phase 7.

**Measured at the end of Phase 7 (2026-10-02).** Raw size, then gzip -9, which
is about what the server's compression sends:

| Piece | Raw | Compressed | Against the budget |
|---|---|---|---|
| A page's HTML (sample library) | 2.3 to 11.1 KB | 1.1 to 2.8 KB | Within; the largest is a circuit map |
| `app.css` | 19.2 KB | 5.0 KB | Over 15 KB raw (the retro design) |
| `app.js` | 16.2 KB | 4.7 KB | Over 15 KB raw (dialogs, circuit and book buttons) |
| `editor.css` / `editor.js` | 3.2 / 13.9 KB | 1.2 / 4.2 KB | `editor.js` over 10 KB raw |
| `map.css` / `map.js` | 3.2 / 11.6 KB | 1.3 / 3.7 KB | `map.js` over 8 KB raw |
| `books.css` | 4.5 KB | 1.4 KB | No budget set; book pages only |
| `logo.svg` | 5.2 KB | 2.7 KB | Every signed-in page, cached |
| Quill (`quill.js`, `quill.core.css`) | 204.4 / 10.0 KB | 57.6 / 1.7 KB | As expected; edit pages only |
| Fonts | Lora 46 KB a weight, Space Grotesk 112 KB a weight, JetBrains Mono 264 KB | 27, 55 and 125 KB | Space Grotesk over 120 KB raw; JetBrains Mono loads only where code shows |

Every asset is versioned and cached for a year, so after the first visit a page
costs only its HTML. The scripts that run over budget do so by a few KB, all
under 5 KB compressed; splitting them would add requests for no real gain.

### 8.2 Layout and look

- A menu bar: the Braim logo (`assets/web/logo.svg`) in the left corner, a
  **File** menu (New note, New Markdown note, Add a link, Find…, Log out),
  then one menu title per section (**Notes**, **Sparks**, **Circuits**,
  **Books**), the current one underlined; a search box and a small dot at the
  right show the phone connection state.
- Content in a centred column; the notes feed is a responsive masonry of cards
  built with CSS columns, pinned first, in the phone's sort order.
- Light and dark from `prefers-color-scheme`. Note colour tags show as small
  swatches in the `NoteColors` colour.
- Fonts from the phone's bundle through `/fonts/<file>`, with
  `font-display: swap`: Space Grotesk for the chrome (menus, title bars,
  buttons, card titles), Lora for everything you read (note bodies, snippets,
  spark text), JetBrains Mono for labels, counts, code and the Markdown
  source. The phone's
  body font setting does not apply on the web. `font-weight` never exceeds
  700.
- **Layout (owner, 2026-10-01):** every page is a window on a desk, after the
  owner's picture of a classic Finder screen. The Notes, Sparks, Circuits and
  Books lists are windows with an info bar ("11 items" and the page's
  action); a note or spark is a window whose close box goes back and whose
  title bar holds **Edit**; editors keep the save state and **Done** in the
  title bar, and the close box is Done too; search is a list; pairing, errors
  and questions are dialogs.
- **Theme (owner, 2026-10-02, replacing the black-and-white retro look):**
  Retro's colours and manner, taken from their site's own design tokens.
  Light: a beige desk (`#FFF0E5`) with a fine dot grid; white panels with
  thin navy (`#10162F`) borders and 8 px corners under navy title bars;
  buttons with 4 px corners and 2 px borders, the call to action yellow
  (`#FFD300`) and lifting onto a hard navy shadow on hover; hyper blue
  (`#3A10E5`) for links, focus, the current tab's underline and ticked
  checkboxes; cards that lift onto a hard shadow; code blocks white on navy;
  notices as navy toasts. Dark: their navy (`#0A0D1C` desk, `#10162F`
  panels) with lime (`#AEE938`) as the accent.
- **Desk accessories (owner, 2026-10-02):** small utility windows after
  TypeSafe's site (typesafe.ai), on the Notes page above its window: a dated
  window with the link to the phone and New note, a clock, and a Game of
  Life glider. A boot window with a progress bar shows once per browser
  session (a click or `Esc` skips it), and every page ends with a mono system
  line ("Braim Web runs on your phone…"). The accessories sit outside `main`,
  so a live refresh leaves them running; the glider pauses in a hidden tab
  and stays still, like the boot window, for `prefers-reduced-motion`.
- 44 px touch targets on touch screens, a visible focus outline,
  `prefers-reduced-motion` honoured. Keep new pages in this language.
- Keyboard: `/` focuses search, `e` edits the open item, `Ctrl+S` saves,
  `Esc` leaves the editor.

### 8.3 Pages

- **Pair.** Six single-digit inputs that auto-advance and accept a pasted
  code. States: wrong code, locked for N seconds, too many browsers, code
  expired. A line: "Find the code in Braim on your phone: Settings, Braim
  Web."
- **Notes feed.** `webFeedNotes`. Circuit first notes render as a circuit
  card, like the phone's. **New note** in the window's info bar; **New note**
  and **New Markdown note** in the File menu.
- **Note view.** Title, then blocks in order: text blocks as HTML (9.1), image
  blocks as `<img src="/img/...">`, link blocks as small link cards. Markdown
  notes render sanitised Markdown. Tags and the colour tag display only.
  Checklist boxes are clickable (`/api/notes/<id>/check`). Circuit notes show
  a breadcrumb, **Map**, **+ Next to this**, **+ Under this** (9.3).
  Book pages show "In {book}" and **Back to contents**.
- **Sparks.** A grid with cover, title, site and snippet; **Add a link**
  takes a URL. The spark page shows the stored preview, the link, the YouTube
  description and transcript, the reader-mode article text, and the spark's
  own note.
- **Search.** Notes and Sparks sections, in the same order the phone's search
  shows.
- **Circuits.** The list of circuits, then the map (9.3).
- **Books.** Shelf with covers, contents, reader, page editor (9.4).
- **Not on Braim Web.** For links to items out of scope, such as journal
  entries: "Open this on your phone."

### 8.4 Live updates and liveness

- `/api/events` is an `EventSource` stream. The hub listens to AppState and
  sends `event: changed` with `{"rev": revision}`, throttled to at most one
  every 500 ms. A comment line every 25 seconds keeps the connection open.
- On `changed`:
  - list pages refetch their own URL with `?partial=1` and swap `<main>`;
  - a view page fetches `/api/notes/<id>/meta` (or the spark or book
    equivalent) and reloads if `updatedAt` changed, or shows "Deleted on your
    phone" on 404;
  - an edit page never reloads; if `updatedAt` changed, it shows "Changed on
    your phone" with **Reload** and **Keep editing** (section 11).
- The connection dot turns grey when the stream drops. `EventSource` retries
  on its own; after 60 seconds without a connection the page shows "Braim Web
  is off, or your phone is out of reach."
- While `document.visibilityState` is `visible`, `app.js` sends `/api/ping`
  every 5 minutes (6.1 auto-off).
- One event stream per tab. Browsers allow about six connections per address
  over HTTP/1.1, so many open tabs will queue; note it in the README.

---

## 9. Content

### 9.1 Rich notes (Delta)

**Reading.** Convert each text block with `richToStyledLines(block.text)`,
which already handles Delta JSON and legacy plain text, then emit:

| `RichLine` | HTML |
|---|---|
| `header` 1 or 2 | `h2`, `h3` (the page title is the `h1`) |
| `quote` | `blockquote` |
| `kind` bullet, ordered | `ul` / `ol` items; group consecutive lines |
| `kind` checked, unchecked | a checklist `li` with a checkbox carrying `data-block` and `data-line` indexes, as `richToLines` counts them |
| `indent` | class `indent-1` to `indent-3` |
| `align` | class `align-center`, `align-right`, `align-justify` |
| runs | `strong`, `em`, `u`, `s`, `mark` for highlight, `a` for links |

Inside each run, split text with `splitWikiSpans`: `[[Title]]` becomes a link
to `/link?to=Title`; `[[@Name]]` becomes a styled span, since Reflexes are out
of scope.

**Editing.** One Quill editor per text block, stacked in block order. Image
and link blocks show between them, read-only, and are kept as they are.

- Load each text block's Delta: parse `block.text` as JSON when it starts with
  `[`; otherwise treat it as plain text, `[{"insert": "<text>\n"}]`.
- Restrict Quill to Braim's formats with the `formats` option:
  `bold italic underline strike link background color header blockquote list
  indent align`. Pasted content keeps only these; embeds such as pasted images
  are dropped.
- Toolbar, mirroring the phone: Body / Heading / Sub-heading (header null, 1,
  2), bold, italic, underline, strike, **highlight**, link, bullet list,
  numbered list, checklist, quote, indent out, indent in, alignment.
- **Highlight** sets `background: #FFE082` and `color: #202124` together, and
  clears both together, matching `kHighlightBg` and `kHighlightInk` in
  `note_body_editor.dart`.
- Checklists use Quill 2's `list: checked` and `list: unchecked`, which match
  `flutter_quill`.

**Saving.** `PUT /api/notes/<id>`:

```json
{
  "baseUpdatedAt": 1790000000000,
  "title": "Groceries",
  "blocks": [ {"id": "b1", "delta": [ {"insert": "Milk\n"} ]} ]
}
```

- Only text blocks appear; each `id` must be an existing text block of that
  note. Unknown ids are rejected with 400; image and link blocks are untouched.
- The server re-applies the format allowlist to every op's attributes, drops
  non-string inserts, and ensures each Delta ends with `\n`. Then it sets
  `block.text = jsonEncode(ops)` and the title, and calls `upsertNote`.
- `baseUpdatedAt` must equal the note's current `updatedAt` in milliseconds,
  else 409 (section 11).
- A web-created note is only added to the library on its first save with
  content, as on the phone.

**Checklist ticks** from the view page use `toggleChecklistLine(block.text,
line)` on the live block, check `baseUpdatedAt`, then `upsertNote`.

### 9.2 Markdown notes

- View: sanitised HTML from `markdownSource` (5.5). Wiki-links inside the
  Markdown become `/link?to=...` links.
- Edit: a monospace `<textarea>` and a **Preview** toggle that posts to
  `/api/markdown/preview`.
- Save: `{baseUpdatedAt, source}`. The server sets the single text block to
  the source and `title = markdownTitle(source)`, then `upsertNote`. An
  emptied Markdown note is deleted the way the phone's Markdown screen does,
  except circuit branches, which are kept (Circuits guide, section 9).

### 9.3 Circuits

- **List:** web-visible circuit first notes, newest first, with branch counts
  (`circuitBranchCount`).
- **Map:** build `children` exactly as `_layoutFor` in
  `circuit_map_screen.dart` does, call `layoutCircuit` with the root's
  `circuitLayout`, and render server-side:
  - one `div.canvas` sized to `canvasSize`;
  - an `svg` layer with one `path` per edge, using the same shapes as
    `_EdgePainter`: cubic curves through the midpoint for left-to-right and
    top-down, straight lines for radial;
  - one absolutely positioned `a.node` per node at its rect: title with two
    lines at most, colour from `NoteColors`, the first note outlined,
    placeholders dashed and muted, a Markdown badge where relevant;
  - a **+** button at `plusAnchor` for each non-placeholder node, and a **⋯**
    button that opens a small menu.
- **`map.js`:** pan by dragging, zoom with the wheel and with trackpad pinch,
  **Fit** and **Centre on focus** buttons, a CSS `transform` on `div.canvas`,
  zoom limited to 0.15 to 2.5. `?focus=<id>` centres and briefly highlights
  that node.
- **Node menu:** Open, Rename, Add note next to this, Add note under this, Add
  Markdown note under this, Move up, Move down, Delete. First note: Open,
  Rename, the Add items, Delete circuit. Placeholders: Write a note here, Write
  a Markdown note here, Remove placeholder. Layout switch in the map header.
- **Delete** follows the phone's rules: a branch with children offers
  **Delete all N+1** and **Delete only this note**, the latter leaving a
  "Placeholder #N". Deleting a circuit asks first and returns to the list.
- **Titles.** Pass `(n) => l10n.circuitNoteTitle(n)` and
  `(n) => l10n.circuitPlaceholderTitle(n)` to the AppState methods, where
  `l10n` is `lookupAppLocalizations(const Locale('en'))`.
- **After adding,** go to the new note's edit page. **Map** and the note's
  add buttons return to `/circuits/<root>?focus=<id>`.
- **New circuit:** `POST /api/circuits {title}` takes
  `newCircuitRootDraft()`, sets the title and calls `ensureCircuitRootSaved`,
  then opens the first note's editor.
- **Not on the web in this version:** indent, outdent, move to, filling a
  placeholder with an existing note, show in Home feed, collapse, share or PDF.

### 9.4 Books

- **Shelf:** `books`, with cover (`/img/`), title and author.
- **Contents:** description, then `bookPages(id)` in order, excluding the
  Contents page, each with **Read** and **Edit**, and **↑** / **↓**
  (`reorderBookPages` with indexes into `bookPages`). **Add chapter** calls
  `addBookChapter`.
- **Reader:** every page except Contents, in order, rendered as 9.1 in the
  book's `fontFamily` (served from `/fonts/`). Quiet matter
  (`BookPageKind.isQuietMatter`) is centred and italic, without a heading.
- **Page editor:** the rich editor from 9.1, plus the page title.
- **Not on the web in this version:** covers, workshop notes, exports, find and
  replace, chapter history, annotations, targets and statuses, front and back
  matter, deleting pages. `deleteBookPage` is a hard delete with no trash, so
  it stays phone-only.

### 9.5 Sparks

- **List:** the `cards` feed. Cover from `coverImageUrl`; title from
  `noteTitle`, else `authorName`, `siteName` or the URL.
- **Add:** `addCardFromUrl(url)`. The phone fetches the preview; the page
  updates through the event stream.
- **Edit:** title field plus the spark's own note blocks, with the 9.1 editor,
  saved through `updateCard`.
- **Delete:** `deleteCard`, a soft delete.
- Scraped text (`text`, `articleText`, `videoDescription`, `videoTranscript`)
  is always escaped, never rendered as HTML.

---

## 10. Search

Extract the merge in `lib/widgets/universal_search.dart` (full-text hits
first, then substring matches, restricted to the searchable lists) into a pure
function in `lib/services/library_search.dart`:

```dart
Future<({List<Note> notes, List<TweetCard> cards})> searchLibrary(
    AppState state, String query);
```

The phone widget and the web both call it, so their results match. Keep the
widget's output identical and prove it with a test. The web filters notes
through `isWebVisibleNote` as well. Archived results stay phone-only.

---

## 11. Concurrent edits

The phone and the laptop can have the same note open. Two mechanisms prevent
lost edits.

**Edit leases** (in AppState, memory only):

```dart
/// Holders: 'phone', or 'web:<sessionId>'.
bool acquireEditLease(String itemId, String holder, {Duration? ttl});
void releaseEditLease(String itemId, String holder);
String? editLeaseHolder(String itemId); // null when free or expired
```

- A lease is free, or held by one holder. Acquiring an item held by another
  holder fails. The same holder may renew.
- Web leases have a 60-second lifetime, renewed by `editor.js` every 20
  seconds. The phone's leases never expire; they are released explicitly.
- **Phone editors** (`NoteEditorScreen`, `MarkdownNoteScreen`,
  `CardDetailScreen`): acquire `'phone'` when editing starts, including notes
  that open straight into edit mode, and release on finishing, closing and
  `dispose`. If the lease is held by the web, stay in reading mode and show
  "Being edited on your computer".
- **Web editors** acquire on load. If the phone holds the lease, the page
  opens read-only with "Being edited on your phone" and **Try again**.
- Every web mutation of an item, including delete, needs the lease or a free
  item.

**Version check.** Every web save and tick sends `baseUpdatedAt`. If the item
changed since the page loaded, answer 409; the page says "Changed on your
phone" and offers **Reload** and **Copy my text**.

**Phone views must refresh.** `NoteEditorScreen` and `MarkdownNoteScreen`
already watch AppState. `CardDetailScreen` does not; make its reading view
rebuild when the card changes, for example with
`context.select<AppState, int?>((s) => s.cardById(_card.id)?.updatedAt.millisecondsSinceEpoch)`.

---

## 12. Strings

Add to `lib/l10n/app_en.arb`, then run `flutter gen-l10n`. Reuse existing keys
where the wording matches (`delete`, `cancel`, `save`, `circuitMoveUp`,
`circuitDeleteAll` and the other circuit keys).

| Key | English |
|---|---|
| `webSection` | Braim Web |
| `webToggle` | Open Braim on your computer |
| `webHint` | Works on the same Wi-Fi, or when your computer joins this phone's hotspot. |
| `webAddressLabel` | Open this address on your computer |
| `webCodeLabel` | Pairing code |
| `webCodeExpires` | New code in {seconds}s |
| `webLinkedBrowsers` | Linked browsers |
| `webLogOut` | Log out |
| `webLogOutAll` | Log out all |
| `webTrustNote` | Your notes stay on this phone. Anyone on this Wi-Fi could read the traffic, so use it on networks you trust. |
| `webNoNetwork` | Connect to Wi-Fi or turn on your hotspot first |
| `webNotificationTitle` | Braim Web is on |
| `webTurnOff` | Turn off |
| `webAutoOff` | Braim Web turned off after 30 minutes without use |
| `webEditingOnComputer` | Being edited on your computer |
| `webPairTitle` | Link this browser to Braim |
| `webPairHelp` | Find the code in Braim on your phone: Settings, Braim Web. |
| `webPairWrong` | That code didn't match |
| `webPairLocked` | Too many tries. Wait {seconds} seconds. |
| `webPairFull` | Too many linked browsers. Log one out on your phone. |
| `webPairNewAddress` | If your phone's address changes, you'll need to link again. |
| `webPairLink` | Link |
| `webPairExpired` | That code has expired. Use the new one on your phone. |
| `webNotFound` / `webError` | Not found / Something went wrong |
| `webBrowserOn` / `webUnknownBrowser` | {browser} on {os} / Browser (linked-browser labels) |
| `webNoBrowsers` | No browser is linked yet. |
| `webLastSeen` | Last used {when} |
| `webStartFailed` | Braim Web couldn't start. Try again. |
| `webSearch` / `webSearchPrompt` | Search / Search your notes and sparks. |
| `webFeedEmpty` / `webSparksEmpty` | No notes yet. / No sparks yet. |
| `webPinned` / `webConnected` | Pinned / Connected to your phone |
| `webEditingElsewhere` | Being edited in another browser |
| `webMenuFile` / `webFind` | File / Find… |
| `webLoading` / `webBootItems` | Loading… / Notes, sparks, circuits, books |
| `webClock` / `webLife` | Clock / Game of Life |
| `webFooter` | Braim Web runs on your phone. Your notes stay on your network. |
| `webPrint` / `webTags` / `webNoColour` / `webColourN` | Print… / Tags / No colour / Colour {n} |
| `webImageTooBig` / `webImageType` | Images can be up to 10 MB. / Use a JPEG, PNG, GIF or WebP image. |
| `webBadLink` | That isn't a web link. Paste one that starts with http:// or https://. |
| `webAddLinkHint` | Paste a link |
| `webSaving` / `webSaved` / `webSaveFailed` | Saving… / Saved / Not saved. Check the connection and try again. |
| `webMarkdownSource` / `webPreview` / `webSubheading` / `webDeleteNote` | Markdown / Preview / Sub-heading / Delete note |
| `webTabNotes` / `webTabSparks` / `webTabCircuits` / `webTabBooks` | Notes / Sparks / Circuits / Books |
| `webNewNote` / `webNewMarkdown` / `webAddLink` / `webNewCircuit` | New note / New Markdown note / Add a link / New circuit |
| `webEditingOnPhone` | Being edited on your phone |
| `webTryAgain` | Try again |
| `webChangedOnPhone` | Changed on your phone |
| `webReload` / `webKeepEditing` / `webCopyText` | Reload / Keep editing / Copy my text |
| `webDeletedOnPhone` | Deleted on your phone |
| `webOffline` | Braim Web is off, or your phone is out of reach. |
| `webNotAvailable` | Open this on your phone |
| `webFit` / `webCentre` | Fit / Centre |
| `webCircuitsEmpty` | No circuits yet. |
| `webAddChapter` / `webRead` / `webBackToContents` | Add chapter / Read / Back to contents |

---

## 13. Build phases

### Phase 0: Orient (no code)
- [x] Read sections 1 to 5, 11 and 15, and the files in section 4.
- [x] Record the baseline: analyzer clean, test count.
      2026-09-30: `flutter analyze --no-pub` no issues; `flutter test --no-pub`
      206 passing.
- [x] Run `git status`; note the owner's unrelated changes and leave them alone.
      2026-09-30: clean tree apart from this file (untracked); `main` is 2
      commits behind `origin/main` (not pulled).

### Phase 1: Server core (no phone UI)
- [x] Dependencies; `assets/web/` listed in `pubspec.yaml`.
- [x] `web_server.dart`, `web_security.dart`, `web_auth.dart`,
      `web_events.dart`; pipeline order (7.2).
- [x] Pairing page and API, session store and file, logout.
- [x] Static assets and fonts from the bundle; a placeholder home page.
- [x] `isWebVisibleNote`, `webFeedNotes`, `webImageNames` in AppState.
- [x] Tests, calling the shelf handler directly with `Request` objects and a
      fake `connection_info` in the context:
  - host allowlist accepts the phone's addresses and localhost, rejects any
    other host; remote address outside private ranges rejected;
  - code: 6 digits, expiry, single use, rotation and 30-second lock after 5
    misses, constant-time compare, 5-browser cap;
  - session: cookie flags, only the hash stored, reload from file, expiry,
    log out and log out all; no session redirects pages and 401s the API;
  - CSRF: mutations without the header get 403;
  - every HTML response carries the CSP and the other headers;
  - `webFeedNotes` ignores the phone's tag filter; `isWebVisibleNote` refuses
    Crypt, deleted, archived, journal and placeholder notes and accepts live
    book pages.

Phase 1 notes (2026-09-30; analyzer clean, 260 tests passing):

- Tests: `test/web_auth_test.dart`, `web_events_test.dart`,
  `web_server_test.dart` (handler-level, plus one real-socket test for port
  fallback, the loopback Host rule and gzip), `web_visibility_test.dart`, and
  `web_assets_test.dart` (loads through `rootBundle`, so it fails if
  `pubspec.yaml` stops listing `assets/web/`).
- Dependencies: `shelf`, `shelf_router`, `crypto`; dev `fake_async` for the
  timer tests (Phase 2's controller tests can use it too).
- `assets/web/vendor/` is not in `pubspec.yaml` yet: Flutter rejects a listed
  folder that doesn't exist. Add it with Quill in Phase 4.
- The CSRF token is not stored: it is `HMAC-SHA256(session token,
  "braim-csrf")`, computed per request from the cookie.
- `autoCompress` only gzips bodies sent without a length, so the
  `compressible()` middleware drops `content-length` from HTML, CSS, JS, JSON
  and fonts. Event streams opt out of buffering (`shelf.io.buffer_output:
  false`), which also keeps them uncompressed.
- `/api/pair` accepts `application/json` only (415 otherwise), so a plain
  cross-site form cannot post to it.
- `BraimWebServer` already has `logOut`, `logOutAll`, `onActivity`,
  `addresses` and `privateAddresses()` for Phase 2's controller. The event hub
  (`events.anyConnected`) listens to AppState only while a stream is open.
- `esc` is `HtmlEscape()`, which also writes `/` as `&#47;` in attributes.
  Browsers decode it; tests that look for URLs in HTML must decode it too.

### Phase 2: Phone switch
- [x] `BraimWebController`, provided in `main.dart`.
- [x] Settings section (6.3) and its strings.
- [x] `BraimWebService`, manifest entries, `braim/web` channel, Turn off
      action, `stopWithTask`.
- [x] Auto-off after 30 minutes; interface refresh every 30 seconds.
- [x] Tests for the controller's start, stop and auto-off timing with a fake
      clock.
- [x] Analyzer, tests, emulator build, owner test script: turn on, pair from
      the laptop through `adb forward`, see the placeholder page, log out from
      the phone, auto-off. (2026-10-01: analyzer clean, 276 tests passing,
      installed on braim_test; script handed to the owner.)

Phase 2 notes (2026-10-01):

- Files: `lib/web/web_controller.dart`, `lib/services/braim_web_service.dart`
  (the `braim/web` channel; a no-op off Android),
  `lib/widgets/braim_web_settings.dart` (the Settings panel), and
  `android/app/src/main/kotlin/com/solo/braim/BraimWebService.kt`.
- One 30-second tick does both jobs: it re-reads the phone's addresses and
  checks auto-off. Auto-off can therefore land up to 30 seconds late. Tests
  drive the tick through `debugTick()` with an injected clock.
- The service is started with the platform `startForeground(id,
  notification, type)` on API 29+, not `ServiceCompat`, so it does not depend
  on which `androidx.core` version the plugins bring in.
- An address change updates the notification with `NotificationManager.notify`
  (method `update`), never a second `startForegroundService`, which Android
  may refuse while the app is in the background.
- `MainActivity.onDestroy` stops the service: the Flutter engine and the
  server die with the activity, so the notification must not stay behind.
- Confirmed 2026-10-01 against the Android foreground-service types page:
  `connectedDevice` needs `FOREGROUND_SERVICE_CONNECTED_DEVICE` plus one of
  `CHANGE_NETWORK_STATE`, `CHANGE_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`,
  `NFC`, `TRANSMIT_IR` (or a Bluetooth, UWB or USB grant). No timeout applies.
- Extra strings: `webNoBrowsers`, `webLastSeen`, `webStartFailed`.
- Logging a browser out drops it from memory at once and writes the file
  after, so Settings updates without waiting for the disk.

### Phase 3: Reading
- [x] Layout, tabs, CSS, `app.js`, light and dark.
- [x] Delta to HTML (9.1) with checklists, wiki-links and highlights.
- [x] Markdown to sanitised HTML (5.5).
- [x] Notes feed, note view, Sparks list and view, images, `/link`.
- [x] `searchLibrary` extraction (10) and the search page.
- [x] Event stream and page refresh (8.4), pings.
- [x] Tests:
  - Delta to HTML for every format in the table, and legacy plain text;
  - sanitiser strips `<script>`, `<img onerror>`, `javascript:` links and raw
    HTML blocks, and keeps the allowed tags;
  - spark text containing HTML is escaped;
  - a Crypt note is absent from the feed, search, `/link`, its page (404),
    its images (404) and any map; the same for deleted and archived notes;
  - `searchLibrary` returns what the widget showed before the extraction;
  - `/img` rejects path traversal and names not in `webImageNames`;
  - the event hub throttles to one event per 500 ms.
- [x] Analyzer, tests, emulator build, owner test script.

Phase 3 notes (2026-10-01):

- Tests: `test/web_render_test.dart` (Delta, Markdown sanitiser, scraped
  text, `safeUrl`) and `test/web_reading_test.dart` (pages, partial refresh,
  `/link`, `/img`, Crypt, deleted, archived and journal items, and
  `searchLibrary` against a verbatim copy of the widget's old merge). The
  throttle test is `web_events_test.dart` from Phase 1. "Any map" in the
  Crypt test waits for the map itself (Phase 5).
- `library_search.dart` has two parts: `matchLibrary` (synchronous, which the
  phone widget calls from `build` with its cached index hits, unchanged) and
  `searchLibrary` (async, which the web calls).
- `WebPages` (`web_pages.dart`) builds each page's main area as a `WebView`;
  the server wraps it in the shell or, for `?partial=1`, returns it alone.
  Note bodies and card snippets are cached by a signature of the note's
  content, not only `updatedAt`.
- Only the Notes and Sparks tabs exist; Circuits and Books join in Phases 5
  and 6. "New note", "Add a link" and edit buttons arrive with Phase 4, and
  checklist boxes render disabled until then.
- `GET /api/sparks/<id>/meta` (`{updatedAt}`) backs the spark page's live
  refresh, like the note meta route.
- A Markdown note's title is its own first heading, so the note page draws
  no separate `h1` for it.
- The note body font comes from `body[data-font]` and a fixed set of
  `@font-face` rules in `app.css`; only the face in use is downloaded.
- Sizes now: `app.css` 13.9 KB, `app.js` 7.4 KB (budgets 15 KB each).
- Design pass (2026-10-01, after Phase 3): restyled to the design language
  in 8.2 and switched to Lora throughout. Also fixed: the pairing boxes had
  `maxlength="1"`, so a pasted or autofilled code kept only its first digit.
  `app.css` 15.0 KB, `app.js` 7.5 KB. A local preview with the sample library
  can be run with `flutter test --no-pub build/web_preview/web_preview_test.dart`
  (git-ignored; it prints the address and a pairing code).

### Phase 4: Editing notes and Sparks
- [x] Edit leases in AppState (11), with the phone editors taking and
      releasing them and `CardDetailScreen` refreshing.
- [x] Vendor Quill 2 (latest 2.x) into `assets/web/vendor/` with its licence;
      record the version in `VERSIONS`.
- [x] `editor.js`: one Quill per text block, Braim's toolbar and highlight,
      format allowlist, lease renewals, save, 409 handling, `Ctrl+S`.
- [x] Create, save and delete notes; checklist ticks from the view page.
- [x] Markdown editor and preview.
- [x] Sparks: add from URL, edit, delete.
- [x] Tests:
  - a Delta with every allowed format, as Quill 2 produces it, saves and reads
    back through `richToStyledLines` and `flutter_quill`'s
    `Document.fromJson` unchanged;
  - disallowed attributes and embeds are stripped on save; a missing final
    newline is added;
  - stale `baseUpdatedAt` gets 409; unknown block id gets 400;
  - a phone lease blocks web saves and deletes; an expired web lease frees the
    item; the phone cannot enter editing while the web holds the lease;
  - a web-created note is not added until it has content;
  - Markdown save updates the title from the first heading.
- [x] Analyzer, tests, emulator build, owner test script.

Phase 4 notes (2026-10-01; analyzer clean, 334 tests passing):

- Files: `lib/web/web_api.dart` (JSON handlers and `sanitizeDelta`),
  `assets/web/editor.js`, `assets/web/editor.css` (edit pages only, so
  `app.css` stays near budget), `assets/web/vendor/` (Quill 2.0.3: `quill.js`,
  `quill.core.css`, `LICENSE-quill.txt`, `VERSIONS` with the npm integrity
  hash). Tests: `test/web_editing_test.dart` (API, sanitiser, round trip
  through `richToStyledLines` and `flutter_quill`'s `Document.fromJson`) and
  `test/phone_lease_test.dart` (the phone editors under a browser's lease).
- Quill's licence is registered in `main.dart` (`registerWebLicenses`), so it
  appears with the app's other licences. `quill.js` also bundles parchment,
  quill-delta, eventemitter3 and lodash-es; their full notices were added to
  `LICENSE-quill.txt` in Phase 7.
- Leases: `AppState.acquireEditLease` and friends, holder `kPhoneLease` or
  `web:<sessionId>`, web leases 60 s (`webLeaseTtl`), renewed every 20 s by
  `editor.js`, released on `pagehide` and on log out. The phone editors take
  the lease when editing starts and release it on Done, on close (after the
  delayed save, so a browser can't slip in before it), and on dispose. While
  a browser holds it, they stay in reading mode and say "Being edited on your
  computer"; read-view checklist ticks are refused the same way.
- Phone-side fix found while wiring leases: the phone editors used to copy
  their title field back into the note on several read-mode paths (wiki-link
  taps, copy, size), which would have undone a rename made in the browser.
  `_collect()` now does nothing while reading, and starting to edit refreshes
  the fields from the live note.
- Editing on the web saves itself 1.5 s after typing stops; Done, `Esc` and
  `Ctrl+S` save at once. `e` on a note or spark page opens its editor.
- A save may send a block without an `id`: it becomes a new text block at
  the end (a new note, or a spark that had no note of its own).
- Extra routes: `POST /api/sparks/<id>/check` (ticks in a spark's note) and
  `leaseHolder` on `GET /api/sparks/<id>/meta`. Meta answers `phone`, `web`
  (another browser) or `you`, never another session's id.
- Sizes now: `app.css` 15.8 KB, `app.js` 9.9 KB, `editor.js` 14.1 KB (over the
  10 KB budget, about 4 KB gzipped), `editor.css` 4.0 KB, Quill 209 KB.

Retro redesign (2026-10-01, after Phase 4; analyzer clean, 334 tests
passing): the owner asked for the look of a classic Mac Finder screen, with
the Braim logo in the menu-bar corner, so 8.2 now describes that design.
`app.css` and `editor.css` were rewritten, the pages restructured into windows
(`windowTitleBar` in `web_pages.dart`), and `app.js` gained the File menu
(closes on an outside click or `Esc`; Find focuses search). New strings
`webMenuFile` and `webFind`; the list windows reuse `itemsCount`. Sizes now:
`app.css` 17.9 KB (over the 15 KB budget, about 4 KB compressed),
`editor.css` 3.7 KB.

### Phase 5: Circuits
- [x] Circuits list and map (9.3), `map.js`.
- [x] Node menu actions, delete dialog, placeholder actions, layout switch.
- [x] New circuit; circuit controls and breadcrumb on note pages.
- [x] Tests:
  - the map's node set and edges match `layoutCircuit` for all three modes;
  - add child and sibling produce "Note #N" titles; delete-only leaves
    "Placeholder #N"; delete-all trashes the subtree as one group;
  - placeholders are not openable as notes;
  - a map of a circuit whose first note is not web-visible answers 404.
- [x] Analyzer, tests, emulator build, owner test script.

Phase 5 notes (2026-10-02; analyzer clean, 357 tests passing):

- Files: the circuit handlers in `lib/web/web_api.dart`, the list, map and
  circuit bar in `lib/web/web_pages.dart`, `assets/web/map.js` and
  `assets/web/map.css` (map pages only). Tests: `test/web_circuits_test.dart`.
- The map is drawn on the server from `layoutCircuit`, with the children
  built as the phone's `_layoutFor` builds them and nothing collapsed. Nodes
  are absolutely placed boxes, branches one SVG `path` each in the shapes of
  `_EdgePainter`, and each live note gets a **+** at `plusAnchor`. `map.js`
  pans (drag), zooms (mouse wheel, trackpad pinch, two-finger touch, `+`,
  `-`, `0`), fits the nodes and their **+** buttons, and keeps the view when
  it redraws after a change (its own or the phone's).
- Extra route: `GET /api/circuits/nodes/<id>/menu` returns a node's menu
  items and the texts of its rename and delete dialogs, so the rules and the
  wording stay in Dart and `map.js` only draws what it is given.
- A delete carries the `count` its dialog showed (a circuit's notes, or the
  notes below a branch); if the circuit changed since, the server answers 409
  `changed` instead of deleting something the dialog didn't mention. A delete
  is also refused while any note it would remove is being edited elsewhere,
  and a rename while that note is.
- Dialogs (rename, delete, and the editor's Delete) are drawn by `app.js` as
  retro windows (`braim.dialog`), replacing the browser's `confirm()`.
- Fixed on the way: a list page's live refresh replaced the Add a link form
  and lost its handler (the next submit went to the browser). Forms and the
  circuit buttons are now handled on the document, and the refresh keeps a
  half-typed value and its focus.
- The menu bar lights **Circuits** on a circuit note's page and editor.
- Strings: `webTabCircuits`, `webFit`, `webCentre` and `webCircuitsEmpty` are new;
  New circuit reuses the existing `newCircuit` key (same wording), so
  `webNewCircuit` was not added. The rest reuse the phone's circuit keys.
- Sizes now: `app.js` 16.1 KB and `app.css` 19.6 KB (both over their 15 KB
  budgets, about 5 KB compressed each), `map.js` 11.8 KB (over its 8 KB
  budget, about 3.5 KB compressed), `map.css` 3.3 KB.

### Phase 6: Books
- [x] Shelf, contents with reordering and Add chapter, reader, page editor.
- [x] Tests: reorder keeps `bookOrder` consistent; a new chapter gets the
      next Roman numeral; an archived or deleted book answers 404; workshop
      notes never appear.
- [x] Analyzer, tests, emulator build, owner test script.

Phase 6 notes (2026-10-02; analyzer clean, 368 tests passing):

- Files: the book handlers in `lib/web/web_api.dart` (`visibleBook`,
  `bookPage`, `addChapter`, `moveBookPage`), the shelf, contents and reader in
  `lib/web/web_pages.dart`, `assets/web/books.css` (loaded on the Books tab's
  pages; it holds the `@font-face` rules for EB Garamond, Merriweather and
  Caveat). Tests: `test/web_books_test.dart`.
- A book's typeface reaches its pages by setting `--serif` on the window, so
  the contents, the reader, a page's view and its editor (title included) all
  read in it. Caveat is set larger, as on the phone.
- The ↑ and ↓ move a page one place among the pages the contents lists, so
  the Contents page keeps its place; the server turns that into
  `reorderBookPages` indexes. A move re-dates every page that changes place
  (AppState does), so it is refused (409 `leased`) while any of them is being
  edited elsewhere.
- A book's Contents page opens as the book's contents (`/notes/<id>` and its
  editor redirect there). Book pages keep their own view at `/notes/<id>`,
  with "In {book}" and Read under the title bar and the close box going back
  to the contents; their editor's Done goes back to the contents too.
- The author shown is the book's own `author`; the phone's fallback to the
  signed-in account no longer applies (sign-in was removed).
- Strings: only `webTabBooks` is new. The rest reuse the phone's keys
  (`untitledBook`, `contentsPage`, `addChapter`, `readBook`, `editAction`,
  `chaptersCount`, `wordsCount`, `booksEmptyTitle`, `untitledEntry`), the
  circuit keys `circuitMoveUp`, `circuitMoveDown` and `circuitIn` ("In
  {title}"), whose wording matches.
- Sizes now: `app.js` 16.6 KB, `books.css` 4.6 KB.

### Phase 7: Release preparation
- [x] README: section "3-11. BRAIM WEB" in the handbook voice, including the
      same-network rule, pairing, auto-off, the hotspot tip and the
      trusted-network warning.
- [x] `PRIVACY.md`: a Braim Web section (16).
- [ ] Play Console items (16). Prepared below; the owner submits them.
- [x] Measure and record asset sizes against 8.1.
- [ ] Full owner test script on a real phone (14). Handed to the owner.

Phase 7 notes (2026-10-02):

- README: section 3-11 in the handbook voice, a `web/` line in the Section V
  tree, paragraph 5-6 on how Braim Web is built, and two LICENSE NOTE changes
  (Quill and its bundled packages; JetBrains Mono now also shows code on the
  web).
- `PRIVACY.md`: a "Braim Web" section (off by default, phone as the server,
  pairing, what a linked browser's record holds and that it stays out of
  Android backup, Crypt never served, unencrypted local traffic, auto-off),
  the foreground-service and Wi-Fi permissions, and the date.
- Licences: `assets/web/vendor/LICENSE-quill.txt` now carries the full notices
  of parchment (BSD-3-Clause), quill-delta (BSD-3-Clause per its LICENSE
  file, though its package.json says MIT), eventemitter3 (MIT) and lodash-es
  (MIT), with copyright lines taken from each package's LICENSE on unpkg.
  `registerWebLicenses` lists all five names, so each shows in the app's
  licences page.
- **Play Console, for the owner** (App content):
  1. Foreground service permissions: declare **Connected device** with the
     description in 16, and a short video if Play asks: turn on Braim Web,
     open the address on a laptop, pair, browse, then turn it off from the
     notification.
  2. Data safety: no change expected. Braim Web sends data only to the user's
     own browser on the user's own network, never to the developer or a third
     party; check the form's wording against Google's current definitions.
  3. Privacy policy: publish the updated `PRIVACY.md` at the listed URL.
  4. Release notes: mention Braim Web, that it is off until switched on, and
     the trusted-network warning.

### Phase 8: Optional polish
- [x] Upload images from the laptop into a note (multipart, saved with
      `StorageService.saveImageBytes`, 10 MB limit).
- [x] Remove images from a note on the web.
- [x] Print a note or a book chapter with the browser's print dialog, using a
      print stylesheet.
- [x] Colour tags and tags editable from the web.

Phase 8 notes (2026-10-02; analyzer clean, 381 tests passing):

- Photos: a picture button at the end of a saved rich note's toolbar picks
  one or more files. Each goes up as the raw request body (`POST
  /api/notes/<id>/images`, not multipart: one file per request is simpler to
  bound and check), up to 10 MB (`kWebMaxImageBytes`; `bodyLimitFor` raises
  the limit for that route only). The server reads the type from the first
  bytes (JPEG, PNG, GIF or WebP; anything else, SVG included, is refused),
  saves it with `saveImageBytes`, and adds it at the end of the note with an
  empty line after it, as the phone adds photos. The editor saves first and
  reloads after, so the new image shows in place.
- Removing: each photo in the editor has a remove button (`DELETE
  /api/notes/<id>/images/<blockId>`). The block goes, an empty line it leaves
  touching another is folded away, and the file is deleted through
  `refreshAfterImageRemoval`, as on the phone. Both need the edit lease.
- Tags and colour: a tags field and the phone's eight swatches (plus none)
  under the title of a note's editor, rich or Markdown, saved with the text.
  `tags` is cleaned as the phone's tag editor cleans it (no `#`, lower case,
  split on spaces and commas, no repeats); `color` must be one of
  `NoteColors.swatches` or null. Left out, either stays as it was. Book pages
  keep theirs on the phone, so their editor doesn't show the row.
- Print: **Print…** in the File menu. The print stylesheet keeps only the
  note, spark, chapter or book in ink on white, and starts each page of a book
  on a new sheet when the reader is printed.
- Strings: `webPrint`, `webTags`, `webNoColour`, `webColourN`,
  `webImageTooBig`, `webImageType`; the button labels reuse `addPhotos`,
  `taskRemove` and `noteColor`. Tests: `test/web_polish_test.dart`.
- Bug pass after Phase 8 (2026-10-02; 382 tests passing): every page type
  loaded without script errors or CSP violations, and the create, edit,
  Markdown, tick, spark, circuit and book flows ran end to end in a browser.
  Fixed: File > Add a link and File > New circuit did nothing when already on
  that page (only the hash changed; `app.js` now listens for `hashchange`); a
  link the server refuses (`ftp:`, `mailto:`, `javascript:`) said "check the
  connection" instead of why (new `webBadLink`); passing notices (a refused
  link, a failed tick or map action) now clear after six seconds, while the
  offline and deleted notices stay; a new note's window and tab kept saying
  "New note" after its first save (they now take its title, or a Markdown
  note's first heading); and the desk clock wrapped onto two lines on a phone.
- Sizes after the Retro theme, the desk accessories and Phase 8:
  `app.css` 25.5 KB (6.4 KB compressed), `app.js` 21.2 KB (6.2 KB compressed), `editor.js`
  17.6 KB (5.0 KB compressed), `editor.css` 5.1 KB (1.7 KB compressed).

---

## 14. Verification and handoff

After every phase:

```bash
flutter gen-l10n
flutter analyze --no-pub
flutter test --no-pub
```

After every visible phase, install on the **braim_test emulator only**:

```bash
flutter build apk --debug
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- Never use `flutter install`; it once uninstalled the app and wiped the
  emulator's data.
- **The emulator is not on the laptop's network.** Forward the port, then open
  `http://localhost:8420` on the laptop:

```bash
adb -s emulator-5554 forward tcp:8420 tcp:8420
```

- Do not drive the emulator with adb taps or screenshots. Hand the owner a
  numbered script: what to open, what to tap, what should happen.
- **Real-phone checks are the owner's.** Do not install on the owner's phone
  unless asked. The final script must cover, on a real phone and laptop on the
  same Wi-Fi, and again with the laptop on the phone's hotspot:
  - turn on, pair, browse all four tabs, search;
  - edit a rich note on the laptop, with bold, highlight, a checklist and a
    heading, and confirm it looks the same on the phone;
  - open the same note for editing on both, and confirm the second one is
    refused;
  - edit on the phone while the laptop shows the note, and confirm the laptop
    refreshes;
  - circuit: add under, add next to, rename, delete-only and see the
    placeholder, switch layouts, pan and zoom;
  - book: add a chapter, reorder, read, edit a page;
  - Crypt: put a note in the Crypt on the phone and confirm it vanishes from
    the laptop, including search;
  - lock the phone, wait 20 minutes, and confirm the site still responds;
  - wait 30 minutes with the tab hidden, and confirm auto-off;
  - swipe Braim away from Recents, and confirm the notification disappears
    and the site shows the offline message;
  - log out from the phone, and confirm the laptop is sent to the pairing page.

---

## 15. Pitfalls

- **The phone's tag filter.** `notes` applies the phone's transient tag
  filter. The web must use `webFeedNotes`.
- **Copies.** Editing a copied `Note` or `TweetCard` loses changes or
  overwrites the phone's. Always mutate the live instance.
- **Phone autosave.** Without leases, an open phone editor's autosave
  overwrites web edits every few seconds.
- **Crypt leaks.** Every id-taking route, `/link`, search, maps and `/img`
  must apply section 5.6. Use 404, not 403.
- **XSS from the web.** Spark and article text come from other websites.
  Escape everything; sanitise Markdown; keep the CSP strict on scripts.
- **DNS rebinding and CSRF.** The host check, `SameSite=Strict` and the CSRF
  header all ship together; none of them is enough alone.
- **Delta drift.** Quill must be limited to Braim's formats both in the
  browser and on save, or pasted content introduces formatting the phone
  cannot show.
- **Trailing newline.** `flutter_quill` expects every Delta to end with `\n`.
- **Address changes.** A new phone address is a new site to the browser, so
  it must pair again. Suggest a fixed address in the router, or the hotspot.
- **Guest and café networks** often block devices from reaching each other.
  The phone's hotspot always works.
- **UI isolate.** The server shares the event loop with the phone's UI. No
  synchronous I/O in handlers, and cache rendered HTML.
- **Change storms.** AppState notifies for view-only changes too; throttle the
  event stream.
- **Emulator host names.** Forgetting `localhost` in the host allowlist breaks
  emulator testing; forgetting to restrict it to loopback remotes weakens the
  check.
- **Browsers trying HTTPS.** Always show `http://` in full.
- **Background starts.** Android refuses to start a foreground service from
  the background; start it only from Settings.
- **Asset folders.** `assets/` in `pubspec.yaml` does not include its
  subfolders; list `assets/web/` and `assets/web/vendor/` explicitly.
- **Resource shrinking.** The new service is referenced from the manifest, so
  it is kept. Anything looked up by name at runtime goes in
  `res/raw/keep.xml`, and notification changes must be checked in a release
  build.

---

## 16. Google Play and privacy

- **Plain HTTP is fine for Play.** Android's cleartext rules restrict
  connections the app makes, not a server the app runs. No network security
  configuration change is needed.
- **Foreground service declaration.** Apps targeting Android 14 and later must
  declare each foreground-service type in Play Console (App content,
  Foreground service permissions) with a description of the feature, and Play
  may ask for a short video. Describe it plainly: "Braim Web lets the user
  open their own notes in a browser on their computer over the same Wi-Fi. The
  service keeps the connection available while the phone screen is off, shows
  a persistent notification, and stops when the user turns it off or after 30
  minutes without use." If Play rejects `connectedDevice`, the fallback is
  `specialUse` with the same description.
- **New permissions** are all normal permissions with no prompt:
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`,
  `CHANGE_WIFI_STATE`.
- **Data safety form.** Data goes only to the user's own browser on the user's
  own network, never to the developer or a third party. Review the form
  against Google's current definitions before release; no new declaration is
  expected.
- **Privacy policy.** Add a "Braim Web" section: off by default; serves the
  library only on the local network, to browsers the user pairs with a code;
  nothing is sent to the developer or any server; traffic on the local network
  is not encrypted, so use trusted networks; the Crypt is never served;
  linked browsers can be logged out from the phone. Update the permissions
  list with the foreground service.

---

## 17. Open decisions (defaults chosen; confirm with the owner)

| Question | Default in this guide |
|---|---|
| Port | 8420, then 8421 to 8429 |
| Auto-off | 30 minutes with no requests from any browser |
| Linked browsers | At most 5; each expires 30 days after last use |
| Code | 6 digits, 2-minute life, 5 tries then a 30-second lock |
| Archived items on the web | Not shown |
| Notes in hidden folders | Not in the feed, found by search, as on the phone |
| Sort order | The phone's current sort order |
| Tags and colour tags | Shown, not editable, until Phase 8 |
| Images from the laptop | Phase 8 |
| Circuit editing on the web | Add, rename, reorder, delete, placeholders, layout; the rest phone-only |
| Book editing on the web | Pages, chapters, reorder; the rest phone-only |
| A book's Contents page on the web (added Phase 6) | Shown as the book's contents; its own note never opens. It keeps its place when pages move |
| Moving book pages while one is open elsewhere (added Phase 6) | Refused while any page whose place would change is being edited elsewhere, since moving re-dates them |
| Sessions file in Android's system backup (added Phase 1) | Excluded. `data_extraction_rules.xml` (cloud and device transfer) and `backup_rules.xml` leave out `braim_web_sessions.json`, so a restored phone never trusts browsers linked to the old one |
| Cookie lifetime (added Phase 1) | Renewed on every page load, so a browser in use never has to pair again; the phone still drops a session after 30 idle days |
| Event streams and auto-off (added Phase 1) | Opening or reconnecting an event stream is not activity: it neither resets auto-off nor updates "last seen". Page loads, API calls and visibility pings do |
| Pairing with five browsers linked (added Phase 1) | Refused before the code is checked, so the code is not used up and no miss is counted |
| Markdown sanitiser, script-like tags (added Phase 3) | `script`, `style`, `iframe`, `object`, `embed`, `template`, `svg` and similar are removed with their contents, not unwrapped: their text is code, not prose. Other disallowed tags keep their text, as 5.5 says |
| Markdown links that are neither web, mail nor `/` paths (added Phase 3) | Dropped, keeping the link text (a `notes.md` link has nowhere to go) |
| Note body font on the web (owner, 2026-10-01) | Lora for everything you read; the phone's body font setting (Caveat by default) is not used on the web |
| Chrome font (added with the redesign, kept for the Retro theme) | Space Grotesk, the bundled face closest to Retro's Apercu (Inter is bundled at one weight only); JetBrains Mono stands in for their Suisse Int'l Mono labels; Lora stays for reading. Switching the chrome to Lora is one line in `app.css` |
| A `[[link]]` to a title that doesn't exist (added Phase 3) | The same "Open this on your phone" page as a hidden item, so the web never reveals whether a hidden note has that title |
| An emptied rich note saved from the web (added Phase 4) | Kept, not deleted: the web only deletes with the Delete button. (An emptied Markdown note is deleted on leaving the editor, as on the phone) |
| Deleting circuit notes and book pages from the web (added Phase 4, settled Phase 5) | Circuit notes delete from the map's node menu, which carries the circuit rules; `DELETE /api/notes/<id>` and the editor's Delete stay for plain notes. Book pages stay phone-only |
| Adding from the map vs from a note page (added Phase 5) | From the map, the new note opens in its editor (9.3). From a note page, **+ Next to this note** and **+ Under this note** show the new note on the map, as the phone does |
| A new circuit's title (added Phase 5) | Required: an untitled, empty first note could be cleaned up as an empty note |
| Web edits autosave (added Phase 4) | 1.5 s after typing stops, plus Done, `Esc` and `Ctrl+S` |
| Indent deeper than three levels (added Phase 4) | Saved as level 3, the phone's deepest |
| Wi-Fi lost while on (added Phase 2) | Braim Web stays on and Settings shows "Connect to Wi-Fi or turn on your hotspot first" in place of the address; nothing can reach it meanwhile, and auto-off still applies |

---

## 18. Out of scope for this version

- **Phone-only features:** Journal, Reflexes, the focus timer, folders and
  their management, the Crypt, Archive, Recently Deleted, Settings, backups,
  sample data, share-in.
- **Book extras:** covers, exports, find and replace, history, annotations,
  workshop notes, deleting pages.
- **Circuit extras:** indent, outdent, move to, placing existing notes, show in
  Home feed, collapse, sharing.
- **HTTPS.**
- **Access from anywhere.** A later project. Two routes: the user installs
  Tailscale on phone and laptop, which needs no server from us but means
  extending the host and address checks to Tailscale's addresses and names; or
  a relay server of our own, which means running a server, end-to-end
  encryption and a privacy-policy rewrite. Nothing in this version should
  assume same-network access in a way that blocks either route.
