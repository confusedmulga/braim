# Circuits: Build Guide (Braim)

A build reference for adding **Circuits** to Braim: a note that grows into a
tree of notes, shown and navigated as a zoomable map. Written so an AI coding
agent (Claude Opus 4.8) or a developer can build the whole feature from this
file alone, without the conversation that produced it.

Companion docs: `docs/sqlite-migration-plan.md` (storage architecture) and
`README.md` (the operator's handbook).

---

## 0. How to use this guide

- Work phase by phase (section 12). Do not start a phase until the previous
  phase's checklist is ticked, `flutter analyze --no-pub` is clean and
  `flutter test --no-pub` is green.
- Tick the checkboxes in this file as you go, so a later session can resume.
- Phases 1 and 2 are pure logic with no UI. Build them test-first.
- At the end of every phase with visible UI, install on the emulator and hand
  the owner a numbered test script (section 13). Do not drive the emulator
  yourself.
- Read section 14 (pitfalls) before writing any code. It lists the ways this
  feature can break existing behaviour.
- When something is not decided here, choose the smallest behaviour that loses
  no data, add it to section 15, and ask the owner.

---

## 1. The feature

Decided with the owner on 2026-09-21. The owner's reference image was not
received; the three layouts below cover the likely shapes.

A **Circuit** is a tree of notes.

- **The first note.** A circuit starts with one full note. Its title is the
  circuit's name and it has its own body. It appears in the Home feed as a
  **Circuit card**, the way a Markdown note appears as a Markdown card.
- **Branches.** Every other note in the circuit is a full note, rich or
  Markdown, placed under a parent. Branches nest to any depth.
- **New notes are titled** (owner decision, 2026-09-21). Every note created
  inside a circuit, whether from the note screen's **+**, the map's **+**, the
  long-press Add actions, or by writing into a placeholder, starts with a
  numbered title: "Note #1", "Note #2" and so on. It is never an empty note, so
  the app's empty-note cleanup never deletes it. A new Markdown note starts
  with that title as its first heading.
- **Notes stay inside.** Notes created inside a circuit do not appear in the
  Home feed. The user can long-press a branch on the map and choose **Show in
  Home feed** to also show it there.
- **The map.** A full-screen canvas that pans freely and pinch-zooms. Every
  note is a node joined by branch lines. Three layouts: **left to right**
  (default), **top down**, and **radial** (first note in the centre). The user
  switches layout on the map; the choice is remembered per circuit.
- **On the map:**
  - Tap a node to open that note.
  - A **+** at the outer end of every node adds a child under it, extending the
    branch like roots.
  - Long-press a node for: Rename, Colour, Move up, Move down, Move into the
    note above, Move out one level, Move to..., Add note next to this, Add note
    under this, Add Markdown note under this, Add an existing note under this,
    Show or Hide in Home feed, Remove from circuit, Delete.
- **In any note that belongs to a circuit**, the top bar shows **+**, a
  **circuit map** button, and the existing **⋯** menu.
  - **+** asks for placement, *Next to this note* (same branch, the default) or
    *Under this note* (a child), and type, *Note* or *Markdown*. It creates the
    note, then takes the user to the map with the new note placed and
    highlighted. On the first note only *Under this note* applies.
  - The **map** button opens the map centred on the current note.
- **Creating a circuit.** Long-press the Home pencil button; the menu gains
  **New circuit**, which opens a new, empty first note.
- **Deleting a note that has notes under it** asks whether to delete it and
  everything under it, or delete only this note and keep a **placeholder note**
  in its place. The placeholder is titled "Placeholder #1", "Placeholder #2"
  and so on. Because it has a title it is never an empty note, so the app's
  empty-note cleanup can never delete it and take the branches under it along.
  The placeholder keeps the children attached. Tapping a placeholder offers:
  write a new note here, write a Markdown note here, place an existing note
  here, move a note from this circuit here, or remove the placeholder.
- **Existing notes** can be placed into a circuit, from the map's long-press
  menu or from a placeholder. They then leave the Home feed like any circuit
  note.
- **Search and links.** Circuit notes are found by search, with the circuit's
  name shown, and can be targets of `[[wiki-links]]`.
- **Folders follow the first note.** Moving the first note into a folder, a
  hidden folder, the Archive or Recently Deleted applies to the whole circuit.
- **No circuits in the Crypt** (owner decision, 2026-09-21). A circuit can
  never be moved into the Crypt, and a Crypt note can never be placed into a
  circuit. Every path that could put a circuit note in the Crypt hides that
  option (section 6.8).

---

## 2. Ground rules (must follow)

- **Scope.** The working tree may hold the owner's unrelated uncommitted work.
  Never revert, reformat or restage files you did not change for this feature.
  Commit only when the owner asks, stage only Circuit files, and never add a
  `Co-Authored-By` trailer.
- **Persistence.** Mutate notes in AppState's in-memory lists, then
  `await _persist()`. Never write storage or SQLite directly. `_persist` bumps
  `_rev`, notifies, and debounces a flush that dirty-diffs each note's JSON body
  into SQLite. New `Note` fields therefore persist, back up and restore with no
  schema change. **Do not change the SQLite schema** (`BraimDatabase.schemaVersion`).
- **JSON compatibility.** New `Note.toJson` keys are written only when they
  differ from the default (`if (x) 'x': true`), and `fromJson` reads them with
  defaults. A note that is not in a circuit must serialize byte-for-byte as it
  does today. Existing tests and the DB dirty-diff rely on this.
- **Live instances only.** Pass the `Note` objects that live in AppState to
  screens. Never copy a `Note`: an editor's later `upsertNote` would overwrite
  structural changes made on the map.
- **Opening notes.** Every "open this note" goes through `noteScreen()` in
  `lib/screens/note_open.dart`, which picks the rich or Markdown screen.
- **Chrome.** New screens use `FrostedScaffold` and `FrostedCircleButton` from
  `lib/widgets/frosted_chrome.dart`, so back buttons match the rest of the app.
- **Type.** Bundled fonts stop at weight 700. Never use `FontWeight.w800` or
  `w900`; digits fall back to Roboto. Some existing code does; do not copy it.
- **Colour.** Use `AppPalette` tokens and `NoteColors` from
  `lib/theme/app_theme.dart`. Everything must read in light and dark mode.
- **Strings.** Every user-visible string goes in `lib/l10n/app_en.arb`; run
  `flutter gen-l10n` and read it through `context.t`.
- **Docs.** The README is an operator's handbook with numbered sections and no
  em dashes. Match its voice.
- **Known dead end.** Android predictive-back peek cannot work in this app
  (local_auth forces `FlutterFragmentActivity`). Do not investigate it.

---

## 3. Codebase map (read before Phase 1)

| Area | File | Why it matters |
|---|---|---|
| Note model | `lib/models/note.dart` | New fields. `isEmpty`, `markdown`, `markdownSource`, `textPreview`, `colorValue` |
| All state | `lib/state/app_state.dart` | `_isFeedNote`, memoized `notes` getter, `searchableNotes`, `_isLinkableNote`, `linkTargets`, `noteById`, `upsertNote`, `deleteNote`, `restoreNote`, `permanentlyDeleteNote`, `emptyTrash`, `_purgeExpiredTrash`, `bulkDeleteNotes`, `bulkArchiveNotes`, `bulkMoveNotes`, `createLinkedNote`, `addMarkdownNode`, `_applyData`, `_snapshot` |
| Closest precedent | `app_state.dart`: `bookPages`, `addBook`, `deleteBook`, `reorderBookPages` | Book pages are notes owned by a parent, ordered, hidden from the feed and cascade-deleted. Circuits follow the same pattern |
| Routing | `lib/screens/note_open.dart` | `noteScreen(note, isNew:)` |
| Rich note screen | `lib/screens/note_editor_screen.dart` | `topActions` BubblePill, `_showNoteMenu`, `_close`, `_persistLater` (deletes emptied notes), `_createAndOpenLinkedNote` |
| Markdown screen | `lib/screens/markdown_note_screen.dart` | `actions` list, `_save` (deletes emptied notes), `_leave`, `_openWikiLink`, `_confirmDelete` |
| Create menu | `lib/screens/root_shell.dart`: `_showCreateMenu`, `_newMarkdown` | Add "New circuit" |
| Home feed | `lib/screens/home_screen.dart` | GlassMorph `openBuilder`, long-press `showQuickActions`, multi-select `_selected` with the `bulk*` calls, `_pickTheme` |
| Feed card | `lib/widgets/note_card.dart`: `_markdownBody` | Template for the Circuit card |
| Search | `lib/widgets/universal_search.dart` | Uses `state.searchableNotes`; builds result subtitles |
| Trash UI | `lib/screens/recently_deleted_screen.dart` | Lists `state.deletedNotes` |
| Colour picker | `lib/widgets/note_background.dart`: `showNoteStylePicker` | Reuse for node colour, as `_pickTheme` does |
| Text prompt | `lib/widgets/text_prompt.dart`: `promptForText` | Rename |
| Confirm, quick actions | `lib/widgets/quick_actions_menu.dart`: `confirmDeleteItems`, `showQuickActions` | |
| Folder picker | `lib/widgets/move_to_space_sheet.dart` | Gains `allowCrypt` (section 6.8) |
| Add-to-folder sheet | `lib/widgets/add_to_space_sheet.dart` | Opened inside a folder, including the Crypt; must exclude circuit notes (section 6.8) |
| Folder setters | `app_state.dart`: `moveNoteToSpace`, `bulkMoveNotes` | Refuse circuits for the Crypt (section 6.8) |
| Chrome | `lib/widgets/frosted_chrome.dart` | `FrostedScaffold(title, actions, body, floatingActionButton, onBack, bodyUnderChrome)`; `FrostedCircleButton.size` is 50 |
| Seed | `lib/services/seed_data.dart`: `SeedData.build` | Sample circuit |
| Test harness | `test/app_state_test.dart` | `_FakePathProvider`, `newState`, `boot`, teardown flush. Copy this pattern |
| DB tests | `test/db_snapshot_test.dart`, `test/db_store_test.dart` | FFI SQLite round trips |

---

## 4. Data model

Add to `Note`: constructor parameter, field, `toJson`, `fromJson`.

| Field | Type, default | JSON written when | Meaning |
|---|---|---|---|
| `circuitId` | `String?`, null | non-null | Id of the circuit's first note. On the first note it equals the note's own id |
| `circuitParentId` | `String?`, null | non-null | Parent node. Null for the first note |
| `circuitOrder` | `int`, 0 | not 0 | Position among siblings, contiguous from 0 |
| `circuitShowInFeed` | `bool`, false | true | Branch is also shown in the Home feed |
| `circuitPlaceholder` | `bool`, false | true | Node is a placeholder, titled "Placeholder #N" |
| `circuitPlaceholderFor` | `String?`, null | non-null | Id of the deleted note this placeholder replaced, used by restore |
| `circuitLayout` | `String`, `'ltr'` | not `'ltr'` | First note only: `'ltr'`, `'ttb'` or `'radial'` |
| `trashGroupId` | `String?`, null | non-null | Any note: shared by notes deleted together; cleared on restore |

JSON keys equal the field names.

```dart
bool get inCircuit => circuitId != null;
bool get isCircuitRoot => circuitId != null && circuitId == id;
bool get isCircuitNode => circuitId != null && circuitId != id; // a branch
```

Rules:

- `id` is final and generated in the constructor, so a first note sets
  `circuitId = id` after construction.
- A branch never carries its own folder: `spaceId` is always null on a branch.
  Folder, Crypt, archive and deletion are read from the first note.
- A branch's `archived` stays false; archiving acts on the first note.
- A placeholder always carries a numbered title, so `isEmpty` is false for it
  and the note screens' empty-note cleanup can never delete it (section 6.5).
- A new branch always starts with a numbered "Note #N" title for the same
  reason (section 6.2).
- A circuit's first note is never put in the Crypt (section 6.8).
- Structural changes (parent, order, placeholder flags, layout, show-in-feed) do
  **not** bump `updatedAt`, so "Modified" reflects content only. Rename and
  colour do bump it.
- Circuits do not nest: a first note is never placed inside another circuit in
  v1.
- No change to `AppData`, the SQLite schema or the backup format. The optional
  viewport memory in Phase 7 would add a settings map following the
  `readerPositions` pattern.

---

## 5. Visibility rules

For a branch, every predicate resolves through its first note (the "root").
Add a memoized id index, a `Map<String, Note>` rebuilt when `_rev` changes, so
`circuitRootOf` is O(1). `noteById` is a linear scan and must never be called
inside a per-note predicate.

Effective values for note `n` with root `r` (`r` is `n` itself for a
non-circuit note and for a root):

- effective folder: `r.spaceId`
- effectively archived: `r.archived`
- effectively deleted: `n.deletedAt != null || r.deletedAt != null`
- in Crypt: effective folder equals `kCryptSpaceId`

Circuits are barred from the Crypt, so the in-Crypt check should never be
true for a circuit. Keep it anyway as a safety net: if a first note is ever
found in the Crypt, for example from an older build or a bug, its branches must
stay hidden rather than leak into search, links or the feed. Never silently
move such a note out of the Crypt.

Placeholders never appear in the Home feed, search or link targets, and cannot
be shown in the Home feed. They are structural, and their "Placeholder #N"
titles would only add noise.

| Surface | First note | Branch | Branch shown in Home feed |
|---|---|---|---|
| Home feed (`notes`) | Yes, as a Circuit card, under the usual rules | No | Yes, as its normal card with an "In {circuit}" chip, only when the first note would be visible in the feed |
| Hidden-folder rule | Uses its own folder | n/a | Uses the first note's folder |
| Folder view (`notesForSpace`) | Yes, when its folder matches | No | No |
| Search (`searchableNotes`) | Yes | Yes, unless effectively archived, deleted or in Crypt | Yes |
| Wiki-link targets, backlinks | Yes | Yes, same exclusions | Yes |
| Archive list | Yes, when archived | No | No |
| Tag list and tag filter | Its own tags | No | Its own tags |
| Recently Deleted | One entry per trash group | One entry per trash group | One entry per trash group |
| Reminders | Fire | Fire | Fire |
| Backups, SQLite, full-text index | Stored | Stored | Stored |
| Pin | Yes | No | Yes, while shown |

Implementation shape:

```dart
bool _isLiveNote(Note n);        // not effectively archived, deleted or in Crypt; not journal; not book page
bool _isFeedNote(Note n) =>
    _isLiveNote(n) &&
    (!n.isCircuitNode || (n.circuitShowInFeed && !n.circuitPlaceholder));
bool _isSearchableNote(Note n) =>
    _isLiveNote(n) && !n.circuitPlaceholder;      // searchableNotes switches to this
bool _isLinkableNote(Note n);     // effective deleted and Crypt; not a book page; not a placeholder
```

- The `notes` getter's hidden-folder check must use the effective folder.
- Search keeps reaching into hidden folders, as today; only the feed applies
  the hidden-folder rule.
- The full-text index already stores every note. `UniversalSearchResults` only
  shows hits present in `searchableNotes`, so Crypt stays out as long as that
  list is right.

---

## 6. State layer (AppState)

Build all of this in Phase 1, headless, with tests. The UI phases only call it.

### 6.1 Queries

```dart
Note? circuitRootOf(Note n);                 // n for a root; null if not in a circuit or root missing
List<Note> circuitChildren(String parentId); // live, sorted by circuitOrder
List<Note> circuitNodes(String circuitId);   // live, root first
int circuitBranchCount(String circuitId);    // live branches, excluding root and placeholders
bool isCircuitAncestor(String ancestorId, String nodeId);
List<Note> circuitPath(String nodeId);       // root to node, for the breadcrumb
List<Note> notesPlaceableInCircuit();        // live feed notes not in a circuit, not journal, not book, not Crypt
```

### 6.2 Creation

```dart
Note newCircuitRootDraft();                        // unsaved first note, circuitId = id
Future<void> ensureCircuitRootSaved(Note root);    // adds the draft to _notes if missing
Future<Note> addCircuitChild(String parentId, {
  bool markdown = false,
  String Function(int n) noteTitle = defaultNoteTitle,
});
Future<Note> addCircuitSibling(String nodeId, {                          // right after nodeId; on a root adds a child
  bool markdown = false,
  String Function(int n) noteTitle = defaultNoteTitle,
});
Future<Note> createLinkedNote(String title, {Note? circuitParent});      // existing method gains the param

String defaultNoteTitle(int n) => 'Note #$n';

/// The smallest n >= 1 whose format(n) is not the title of a live note in
/// this circuit. Shared by new-note titles (6.2) and placeholder titles (6.5).
String _nextNumberedTitle(String circuitId, String Function(int n) format);
```

- **New branches are titled.** Every new branch gets
  `_nextNumberedTitle(circuitId, noteTitle)`: "Note #1", then "Note #2", and a
  number freed by a deleted note is reused. The UI passes the localized
  formatter (`(n) => t.circuitNoteTitle(n)`); tests and generic callers use the
  English default. "Note" and "Placeholder" numbers are independent.
- **Markdown branches carry the title in their source.** The Markdown screen
  derives the title from the first `#` heading (`markdownTitle`) and deletes a
  note whose source is empty, so a title field alone does not protect it. A
  new Markdown branch is created with the source `# Note #N` followed by a
  newline, and the same title in `title`.
- A rich branch gets the title and an empty text block, so `isEmpty` is false.
- `addCircuitChild` appends as the last child. `addCircuitSibling` inserts at
  the node's order plus one and shifts later siblings.
- Both require the parent to exist in `_notes`. The note screen calls
  `ensureCircuitRootSaved(_note)` before **+** or **map** on an unsaved first
  note.
- A `[[link]]` that creates a note from inside a circuit note creates it as a
  child of that note (default; see section 15).

### 6.3 Structure

```dart
Future<void> moveCircuitNode(String nodeId, int delta);            // -1 up, +1 down among siblings; clamps
Future<void> indentCircuitNode(String nodeId);                     // last child of its previous sibling; no-op if first
Future<void> outdentCircuitNode(String nodeId);                    // sibling of its parent, right after it; no-op under the root
Future<bool> moveCircuitNodeTo(String nodeId, String newParentId); // last child; false if invalid
Future<bool> fillPlaceholder(String slotId, String nodeId);        // node takes the slot
Future<void> setCircuitShowInFeed(String nodeId, bool show);
Future<void> setCircuitLayout(String rootId, String mode);         // no updatedAt bump
Future<void> renameCircuitNode(String nodeId, String title);
Future<void> setCircuitNodeColor(String nodeId, int? color);
```

- A node always moves with its whole subtree.
- `moveCircuitNodeTo` is invalid when the target is the node itself, one of its
  descendants, in another circuit, or when the node is the root.
- `fillPlaceholder(slot, node)`: the node and its subtree detach from where they
  were, take the placeholder's parent and order, and adopt the placeholder's
  children after the node's own. The placeholder is removed outright; it holds
  nothing but its "Placeholder #N" title, so it skips the trash. `node` may be a
  branch of the same circuit or a note from `notesPlaceableInCircuit()`.
  Invalid when `node` is the placeholder itself, the root, or an ancestor of
  the placeholder.
- `setCircuitShowInFeed` refuses placeholders.
- After every operation, renumber each affected sibling list to 0..n-1.

### 6.4 Existing notes

```dart
Future<bool> placeNoteInCircuit(String noteId, String parentId); // becomes last child
Future<void> removeFromCircuit(String nodeId);                   // becomes a standalone Home note
```

- Placing clears the note's `spaceId` and `circuitShowInFeed`, so it leaves the
  Home feed and follows the circuit's folder. Only notes from
  `notesPlaceableInCircuit()` are valid.
- Removing a branch clears all its circuit fields. Its children move up to its
  parent at its position. The root cannot be removed.

### 6.5 Deletion and trash

```dart
Future<void> deleteCircuit(String rootId);             // root and every node, one trash group
Future<void> deleteCircuitSubtree(String nodeId);      // node and descendants, one trash group
Future<void> deleteCircuitNodeKeepSlot(               // node alone to trash; a placeholder takes its place and adopts its children
  String nodeId, {
  String Function(int n) placeholderTitle = defaultPlaceholderTitle,
});
Future<void> deletePlaceholder(String slotId);         // removed outright; children move up to its parent at its position

String defaultPlaceholderTitle(int n) => 'Placeholder #$n';

typedef TrashGroup = ({String key, Note top, List<Note> members});
List<TrashGroup> get deletedNoteGroups;                 // for the Recently Deleted list
Future<void> restoreTrashGroup(String key);
Future<void> permanentlyDeleteTrashGroup(String key);
```

- **Placeholder titles.** `deleteCircuitNodeKeepSlot` gives the new
  placeholder the title `_nextNumberedTitle(circuitId, placeholderTitle)`
  (6.2): the smallest positive `n` whose `placeholderTitle(n)` is not already
  used by a live note in the same circuit. The first is "Placeholder #1"; with #1 and #2 present the next is #3;
  if #1 is later removed, the next one reuses #1. The UI passes the localized
  formatter (`(n) => t.circuitPlaceholderTitle(n)`); generic calls such as the
  `deleteNote` routing in 6.7 fall back to the English default. The title is
  what keeps the placeholder from being an empty note: the note screens'
  empty-note cleanup therefore never deletes it, and the branches under it are
  safe.
- A trash group shares one `deletedAt` and one `trashGroupId`. A note deleted
  alone is a group of one, keyed by its id. `top` is the member whose parent is
  not in the group.
- Keep `deletedNotes` as a flat list for counts. The 30-day purge and Empty
  Trash keep working because group members share `deletedAt`.
- Cancel reminders for every deleted member, as `deleteNote` does.
- `restoreTrashGroup`, in order:
  1. Not a circuit group: clear `deletedAt`, as today.
  2. `top` is a root: restore every member.
  3. `top` is a branch whose root is in the trash: restore the root's group
     first, then continue, and tell the user the circuit came back too.
  4. A live placeholder has `circuitPlaceholderFor == top.id`: `top` takes that
     placeholder's place through `fillPlaceholder`.
  5. `top`'s parent is live: append `top` as the parent's last child.
  6. Otherwise append `top` as the root's last child.
  7. The root no longer exists at all: `top` becomes the first note of a new
     circuit and the members follow (`circuitId = top.id` on all of them).
  Clear `trashGroupId` on every restored member.

### 6.6 Integrity repair

Add `_repairCircuits()` and call it in `_applyData` right after
`_purgeExpiredTrash()`. It guards against bad data from restores, older builds
or bugs. It never bumps `updatedAt` and persists only if it changed something.

- A note with no parent whose `circuitId` differs from its id becomes the root
  of its own circuit.
- A live branch whose parent is missing or deleted moves under the root. If the
  root is missing, the topmost surviving ancestor becomes a new root and its
  descendants follow.
- A parent cycle is broken by moving the node under the root.
- Branches get `spaceId = null` and `archived = false`.
- Sibling orders are renumbered 0..n-1, stable by `circuitOrder` then
  `createdAt`.
- A placeholder whose title is empty, for instance one the user blanked out,
  gets a numbered title again (6.5).
- A first note found in the Crypt stays there. Repair never moves a note out
  of the Crypt; the section 5 safety net keeps its branches hidden.

### 6.7 Make the generic methods circuit-safe

Many screens call the generic methods. Route them so no code path can orphan a
branch:

- `deleteNote(id)`: a root calls `deleteCircuit`; a branch with live children
  calls `deleteCircuitNodeKeepSlot`; anything else deletes as today. The UI
  shows the choice dialog first and calls the specific method; this routing is
  the safety net.
- `bulkDeleteNotes`: roots cascade through `deleteCircuit`. Branches are
  skipped (Home multi-select can only hold branches shown in the feed; they are
  managed on the map), with a snackbar saying so.
- `bulkArchiveNotes`, `bulkMoveNotes`: roots already act on the whole circuit
  through inheritance; branches are skipped.
- `restoreNote(id)` and `permanentlyDeleteNote(id)`: act on the note's whole
  trash group.

### 6.8 Folders and the Crypt

Circuits are not allowed in the Crypt. There are three ways a note can reach
it today, and each one must refuse circuits:

1. **The folder picker**, `showMoveToSpaceSheet` in
   `lib/widgets/move_to_space_sheet.dart`, used by the rich and Markdown note
   screens, Home quick actions, Home multi-select, the card screen and
   `item_actions_sheet.dart`. Give it a `bool allowCrypt = true` parameter
   that hides the Crypt row. Pass `allowCrypt: false` whenever the note being
   moved is in a circuit, and for Home multi-select whenever the selection
   holds a first note. Branches never see the picker at all (section 9).
2. **The add-to-folder sheet**, `showAddToSpaceSheet` in
   `lib/widgets/add_to_space_sheet.dart`, opened from inside a folder view,
   including the Crypt's. It lists `state.notes`. Exclude branches from it for
   every folder, and exclude first notes when the folder is the Crypt.
3. **The state setters.** `moveNoteToSpace` returns without change for a
   circuit's first note when the target is the Crypt, and for any branch.
   `bulkMoveNotes` skips the same notes. The UI shows `circuitNoCrypt` when
   something was refused. The note screens set `spaceId` on the note directly
   before saving, so the picker change in point 1 is what protects that path.

Also:

- "New circuit" exists only in the Home pencil menu. Do not add it to a folder
  screen's create button, where it could start a circuit inside the Crypt.
- `notesPlaceableInCircuit()` already excludes Crypt notes, so a Crypt note
  can never be placed into a circuit.
- Moving a circuit into an ordinary or hidden folder stays allowed; the
  branches follow the first note.

---

## 7. Layout engine

`lib/services/circuit_layout.dart`. Pure Dart plus `dart:ui` geometry: no
widgets, no AppState. Everything here is unit-tested.

```dart
enum CircuitLayoutMode { ltr, ttb, radial }

class CircuitMetrics {
  const CircuitMetrics({
    this.nodeW = 184, this.nodeH = 64,
    this.depthGap = 72, this.breadthGap = 18,        // left to right
    this.ttbBreadthGap = 24, this.ttbDepthGap = 64,  // top down
    this.ringGap = 120,                              // radial, must be >= node diagonal + breadthGap
    this.margin = 240,
  });
  // fields...
}

class CircuitLayout {
  final Map<String, Rect> rects;                     // node id to rect, canvas coordinates
  final List<(String parent, String child)> edges;
  final Size canvasSize;                             // bounds plus margin; all rects positive
  final CircuitLayoutMode mode;
  Offset plusAnchor(String id);                      // centre of the node's + button
  Offset outward(String id);                         // unit direction the node grows toward
}

CircuitLayout layoutCircuit({
  required String rootId,
  required Map<String, List<String>> children,       // ordered by circuitOrder
  Set<String> collapsed = const {},
  CircuitLayoutMode mode = CircuitLayoutMode.ltr,
  CircuitMetrics metrics = const CircuitMetrics(),
});
```

Every node is the same size. That keeps all three layouts simple and makes
"no overlaps" provable.

**Core: leaf slots.** Walk depth-first in child order. A leaf takes the next
integer slot. A parent's slot is the midpoint of its first and last child's
slots. Children of a collapsed node are skipped. This gives every visible node
a `depth` and a `breadth`. Two nodes at the same depth are always at least one
slot apart.

**Left to right.** `x = depth * (nodeW + depthGap)`,
`y = breadth * (nodeH + breadthGap)`. Edges run from the parent's right-middle
to the child's left-middle as a cubic curve with both control points at the
horizontal midpoint. The **+** sits just past the right edge.

**Top down.** `x = breadth * (nodeW + ttbBreadthGap)`,
`y = depth * (nodeH + ttbDepthGap)`. Edges run bottom-middle to top-middle with
control points at the vertical midpoint. The **+** sits just below the bottom
edge.

**Radial.** Let `L` be the number of leaf slots (at least 1) and `D` the node
diagonal. A node's centre sits at angle `-pi/2 + 2*pi*(breadth + 0.5)/L`,
clockwise from the top, and at radius:

- `r(0) = 0`
- `r(1) = L < 2 ? ringGap : max(ringGap, (D + breadthGap) / (2 * sin(pi / L)))`
- `r(d) = r(1) + (d - 1) * ringGap`

Same-depth neighbours are at least `2*pi/L` apart, so their chord is at least
`D + breadthGap`; rings are `ringGap >= D + breadthGap` apart. Nothing
overlaps. Edges are straight lines centre to centre, painted under the nodes.
The **+** sits outward along the radius; the first note's **+** sits below it.

Finally shift all rects so the minimum x and y equal `margin`, and set
`canvasSize` to the bounds plus `margin` on every side.

Tests (Phase 2): a single node; a chain; a wide fan-out; a mixed tree. For all
three modes: no two rects intersect; sibling order is preserved along the
breadth axis; every parent's breadth is the midpoint of its first and last
child's; collapsed nodes hide their descendants; the output is deterministic;
every rect lies inside `canvasSize`.

---

## 8. Map screen

Files: `lib/screens/circuit_map_screen.dart`,
`lib/widgets/circuit_node_chip.dart`, `lib/widgets/circuit_edges_painter.dart`,
`lib/widgets/circuit_sheets.dart`.

```dart
CircuitMapScreen({required String circuitId, String? focusNodeId, bool highlight = false})
class CircuitMapFocus { final String nodeId; final bool highlight; }   // pop result from a note screen
```

**Structure.** `FrostedScaffold(title: circuit name or "Untitled circuit",
actions: [layout switch, fit to screen], bodyUnderChrome: true)`. The body is a
`LayoutBuilder` around:

```dart
InteractiveViewer(
  transformationController: _tc,
  constrained: false,
  boundaryMargin: const EdgeInsets.all(double.infinity),
  minScale: 0.15,
  maxScale: 2.5,
  child: SizedBox.fromSize(
    size: layout.canvasSize,
    child: Stack(children: [
      Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: edges))),
      // one Positioned.fromRect(CircuitNodeChip) per visible node
      // one Positioned + button per visible, non-placeholder node, at plusAnchor
    ]),
  ),
)
```

- Build the layout from AppState on each build; it is cheap at personal sizes.
  If profiling shows cost, memoize on a structure key (ids, parents, orders,
  placeholder flags, collapsed set, mode).
- Use the non-deprecated Matrix4 calls on Flutter 3.41 (`translateByDouble`,
  `scaleByDouble`).

**Viewport.**

- Fit: `s = clamp(min(vw / bw, vh / bh) * 0.9, minScale, 1.0)`, then translate
  so the bounds are centred.
- Centre on a node: keep the current scale (1.0 on first open) and translate so
  the node's centre sits at the viewport centre.
- Animate both with a `Matrix4Tween` over about 300 ms.
- On open: centre on `focusNodeId` if given, otherwise fit.

**Node chip.** Rounded rect, radius 16, the metrics size. Title at most two
lines with ellipsis; "Untitled" in italics when empty; text scale clamped to
1.3. Fill `NoteColors.resolveStrong(colorValue)` with `NoteColors.onSwatch`
ink, else `AppPalette.surfaceGlass` with a `cardOutline` border. The first
note gets a primary-coloured border and a small circuit icon. Badges: a
Markdown icon, an "in Home feed" icon, a child count when collapsed. A
placeholder draws a dashed outline, its "Placeholder #N" title in muted ink,
and no colour or + button. The focused node gets a
primary ring, and with `highlight` a pulse of about 1.2 s. Wrap each chip in a
`RepaintBoundary`.

**+ button.** A 28 px circle with a 40 px hit area at `plusAnchor`. Tap calls
`addCircuitChild` with the localized "Note #N" formatter, animates the layout
and centres on the new node, which appears already titled.

**Gestures.** Tap a node to open it (section 9 navigation contract). Long-press
opens the node sheet with `HapticFeedback.selectionClick`. Tap or long-press
a placeholder to open the placeholder sheet; a placeholder never opens in the
editor directly.

**Layout-change animation.** Keep the previous rects. When the new layout
differs, lerp every node and edge from old to new over 250 ms, ease-out cubic.
New nodes start at their parent's old rect; removed nodes vanish. Drive nodes
and edges from the same lerped rects so lines never detach.

**Pick modes.** For *Move to...* and a placeholder's *Move a note here*, the
map enters a pick mode: a frosted banner at the bottom ("Tap where to move
"{title}"" or "Tap the note to move into this placeholder") with Cancel. Invalid
targets are dimmed and ignore taps. A tap on a valid target calls
`moveCircuitNodeTo` or `fillPlaceholder` and leaves the mode. In *Move to...*,
tapping a placeholder fills it.

**Layout switch.** Cycles left to right, top down, radial. The icon reflects the
mode; the choice persists with `setCircuitLayout`; the switch animates and
refits.

### 8.1 Sheets and dialogs

- **Node sheet** (long-press), with the title as a header, in this order:
  Open, Rename, Colour, Move up, Move down, Move into the note above, Move out
  one level, Move to..., Add note next to this, Add note under this, Add
  Markdown note under this, Add an existing note under this, Show in Home feed
  or Hide from Home feed, Remove from circuit, Delete. Disable what does not
  apply, such as Move up on the first sibling.
- **Node sheet for the first note:** Open, Rename, Colour, Add note under this,
  Add Markdown note under this, Add an existing note under this, Delete
  circuit.
- **Colour:** `showNoteStylePicker`, exactly as home_screen's `_pickTheme`.
- **Rename:** `promptForText`.
- **Delete a branch without children:** confirm, then `deleteCircuitSubtree`.
- **Delete a branch with children:** a dialog titled Delete "{title}"?, body
  "It has N notes under it.", buttons **Delete all N+1** (destructive),
  **Delete only this note** (with the hint "Leaves a placeholder so the notes
  under it stay put") and **Cancel**. They call `deleteCircuitSubtree` or
  `deleteCircuitNodeKeepSlot` with the localized placeholder title.
- **Delete circuit:** Delete circuit "{title}" and all its N notes?, then
  `deleteCircuit`, then pop the map.
- **Placeholder sheet** (tap or long-press a placeholder), headed with its
  "Placeholder #N" title:
  - Write a new note here: clear the placeholder flags, retitle it with the
    next "Note #N" (it is now a real note, so it joins the note numbering and
    frees its placeholder number), and open it in edit mode (section 9) so the
    user can rename it straight away.
  - Write a Markdown note here: the same, with `markdown = true` and the source
    seeded as `# Note #N` (6.2).
  - Place an existing note here: the picker, then `fillPlaceholder`.
  - Move a note here: pick mode on the map, then `fillPlaceholder`.
  - Remove placeholder: `deletePlaceholder`; its children move up to its
    parent.
- **Existing-note picker:** a draggable bottom sheet with a search field over
  `notesPlaceableInCircuit()`, each row showing title and one line of preview.
- **Add sheet** (from the note screen's **+**): placement *Next to this note*
  or *Under this note* (only *Under* on the first note), type *Note* or
  *Markdown*, and **Create**.

---

## 9. Note screen integration

`NoteEditorScreen`, `MarkdownNoteScreen` and `noteScreen()` all gain
`bool fromCircuitMap = false`.

**Top bar.** For a note in a circuit that is not a placeholder: the rich screen
adds two `IconButton`s before the ⋯ inside its `topActions` BubblePill; the
Markdown screen adds two `FrostedCircleButton`s before its actions, in view and
edit mode.

- **+** (`Icons.add_rounded`): save the current note, show the add sheet,
  create the node, then go to the map focused on it with `highlight: true`.
- **Map** (`Icons.account_tree_rounded`): save, then go to the map focused on
  this note.
- On an unsaved first note, both call `ensureCircuitRootSaved(_note)` first.

**Navigation contract** (keeps the stack flat instead of note, map, note,
map...):

- Opening a note from the map pushes it with `fromCircuitMap: true` and awaits
  a `CircuitMapFocus` result.
- In a note opened from the map, **map** and **+** save and pop with a
  `CircuitMapFocus`; the map re-centres, and pulses when highlighted.
- Otherwise they push a new `CircuitMapScreen`.
- The rich screen's `_close` and the Markdown screen's `_leave` gain an optional
  result to pop with.

**Breadcrumb.** Above the title, where the folder chip sits, a small chip
"{circuit} > {parent}" that opens the map focused on this note. Optional but
cheap.

**⋯ menu.** For a branch, hide Archive and Move to folder, since they follow
the first note; Delete runs the section 8.1 dialog. For the first note,
Archive, Move to folder and Delete act on the whole circuit; Delete confirms as
*Delete circuit*, and Move to folder opens the picker with
`allowCrypt: false` (section 6.8).

**Empty notes must survive (critical).** Today both screens delete a note
that has been emptied: `_persistLater` in the rich screen and `_save` in the
Markdown screen. For a circuit that deletes branches and orphans their
children.

The owner's first line of defence is the numbered title: new notes are created
as "Note #N" (6.2) and placeholders as "Placeholder #N" (6.5), so neither is
ever empty and the cleanup never touches them. One case still reaches the
cleanup: the user can erase a title and leave the body empty. These rules stay
as the backstop for it:

- A branch is never deleted for being empty; save it as it is.
- A first note with branches is never deleted for being empty.
- A first note that is empty and has no branches when its screen closes: if it
  was never saved with content in this session (a draft, or saved only by
  `ensureCircuitRootSaved`), remove it outright with no trash entry; otherwise
  soft-delete it as any emptied note is today.
- "New circuit" opens a draft from `newCircuitRootDraft()` that is persisted on
  its first save with content or its first branch, the same way a new note
  works today.

**Opening a new note ready to type.** Both screens open in reading mode unless
`isNew` is true, but `isNew` also drives the empty-note cleanup and the close
animation, so do not reuse it. Add `bool startEditing = false` to
`NoteEditorScreen`, `MarkdownNoteScreen` and `noteScreen()`. The map passes it
when it opens a circuit note whose body is still empty: for a rich note, no
body text; for a Markdown note, a source that is only its `# Note #N` heading.
The title then sits ready to rename.

**Links.** The rich screen's `_createAndOpenLinkedNote` and the Markdown
screen's `_openWikiLink` pass `circuitParent: _note` when the note is in a
circuit. A linked note keeps the link's text as its title, not a "Note #N".

---

## 10. App integration

- **Create menu** (`_showCreateMenu` in root_shell): add
  `item('circuit', Icons.account_tree_rounded, t.newCircuit)` at the top, and a
  `_newCircuit()` that pushes
  `NoteEditorScreen(note: state.newCircuitRootDraft(), isNew: true)`.
- **Feed card** (`NoteCard`): before the Markdown check,
  `if (note.isCircuitRoot) return _circuitBody(...)`. Mirror `_markdownBody`: a
  "Circuit" badge with the tree icon, the title or "Untitled circuit", two or
  three lines of the first note's body, and a footer with "N notes" plus up to
  three child titles as small chips. Respect the coloured-card ink the way
  `_markdownBody` does. A branch shown in the feed renders its normal card with
  an "In {circuit}" chip where the folder chip goes.
- **Feed tap:** opens the first note via `noteScreen`. Replace home_screen's
  inline `n.markdown ? ... : ...` in `openBuilder` with `noteScreen(n)`.
- **Home long-press quick actions:** for a first note, Pin, Colour, Folder,
  Archive and Delete act on the circuit; Folder opens the picker without the
  Crypt, and Delete confirms as *Delete circuit*. For a branch shown in the
  feed, replace Folder and Archive with *Hide from Home feed*, and route Delete
  through the section 8.1 dialog.
- **Folder views:** the add-to-folder sheet follows section 6.8, so a circuit
  can be added to an ordinary folder but never from inside the Crypt.
- **Search:** switch to `_isSearchableNote`. Branch results get the tree icon
  and the subtitle "In {circuit}".
- **Recently Deleted:** list `deletedNoteGroups`. A group of more than one
  shows its top note with "+ N notes" and the tree icon. Restore and Delete
  forever act on the whole group.
- **Seed data:** add a sample circuit, for example "Plan a trip": a first note
  with a body, about eight branches three levels deep, one Markdown branch, one
  coloured branch, one branch shown in the feed, and one "Placeholder #1" with
  a child. Extend the sample-data test to assert it. Keep its existing counts for
  folders, cards and books unchanged.
- **README:** add "3-10. CIRCUITS" to Section III in the handbook voice, and
  update 2-1 for the new pencil option. Add a **NOTE** advisory: restoring a
  backup into an older Braim build shows circuit notes as loose notes in the
  feed, with nothing lost.
- **Privacy policy:** no change. Circuits are local like every note.

---

## 11. Strings

Add to `lib/l10n/app_en.arb`, then run `flutter gen-l10n`. Reuse an existing
key where the wording fits (for example `emptyNote` or `untitledEntry` for
"Untitled").

| Key | English |
|---|---|
| `newCircuit` | New circuit |
| `circuitLabel` | Circuit |
| `untitledCircuit` | Untitled circuit |
| `circuitMap` | Circuit map |
| `circuitNotesCount` | `{n, plural, =1{1 note} other{{n} notes}}` |
| `circuitIn` | In {title} |
| `circuitMoreNotes` | + {n} notes |
| `circuitAddTitle` | Add to circuit |
| `circuitNextTo` | Next to this note |
| `circuitUnder` | Under this note |
| `circuitTypeNote` | Note |
| `circuitTypeMarkdown` | Markdown |
| `circuitCreate` | Create |
| `circuitRename` | Rename |
| `circuitColour` | Colour |
| `circuitMoveUp` | Move up |
| `circuitMoveDown` | Move down |
| `circuitIndent` | Move into the note above |
| `circuitOutdent` | Move out one level |
| `circuitMoveTo` | Move to... |
| `circuitMoveBanner` | Tap where to move "{title}" |
| `circuitSlotBanner` | Tap the note to move into this placeholder |
| `circuitAddSibling` | Add note next to this |
| `circuitAddChild` | Add note under this |
| `circuitAddChildMarkdown` | Add Markdown note under this |
| `circuitAddExisting` | Add an existing note under this |
| `circuitShowInFeed` | Show in Home feed |
| `circuitHideFromFeed` | Hide from Home feed |
| `circuitRemove` | Remove from circuit |
| `circuitDeleteTitle` | Delete "{title}"? |
| `circuitDeleteBody` | It has {n} notes under it. |
| `circuitDeleteAll` | Delete all {n} |
| `circuitDeleteOnly` | Delete only this note |
| `circuitDeleteOnlyHint` | Leaves a placeholder so the notes under it stay put |
| `circuitDeleteCircuit` | Delete circuit "{title}" and all its {n} notes? |
| `circuitNoteTitle` | `Note #{n}` |
| `circuitPlaceholderTitle` | `Placeholder #{n}` |
| `circuitSlotWrite` | Write a new note here |
| `circuitSlotWriteMarkdown` | Write a Markdown note here |
| `circuitSlotPlace` | Place an existing note here |
| `circuitSlotMove` | Move a note here |
| `circuitSlotRemove` | Remove placeholder |
| `circuitNoCrypt` | Circuits can't be moved into the Crypt |
| `circuitLayoutLtr` | Left to right |
| `circuitLayoutTtb` | Top down |
| `circuitLayoutRadial` | Radial |
| `circuitFit` | Fit to screen |
| `circuitPickNote` | Choose a note |
| `circuitRestoredWithRoot` | The circuit was restored too |
| `circuitBulkSkipped` | Circuit notes are managed on the circuit map |

---

## 12. Build phases

### Phase 0: Orient (no code)
- [x] Read sections 1 to 5 and 14, and the files in section 3.
- [x] Record the baseline: analyzer clean (`No issues found!`), 99 tests green.
- [x] Run `git status`; owner's unrelated changes committed as the font/notification
      batch, the plan doc left untracked and untouched.

### Phase 1: Model and state (no UI)
- [x] Note fields, getters and JSON (section 4).
- [x] Id index, `circuitRootOf`, effective values, new predicates (section 5).
- [x] Queries, creation with numbered "Note #N" titles and seeded Markdown
      sources, structure, existing notes (6.1 to 6.4).
- [x] Deletion, trash groups, restore rules, numbered placeholder titles (6.5).
- [x] `_repairCircuits` wired into `_applyData` (6.6).
- [x] Generic methods made circuit-safe (6.7).
- [x] Crypt barrier in `moveNoteToSpace` and `bulkMoveNotes` (6.8).
- [x] `createLinkedNote(..., circuitParent:)`.
- [x] Tests in `test/circuit_model_test.dart` and `test/circuit_state_test.dart`
      (6 model + 33 state = 39 new tests, all green).
- [x] Existing suite green; no existing test weakened (99 -> 138 tests).

Phase 1 tests:

- A non-circuit note's JSON is byte-identical to before; old JSON without the
  new keys loads with defaults; every new field round-trips.
- Create a circuit; add children and siblings; orders stay contiguous; move up
  and down, indent, outdent; `moveCircuitNodeTo` rejects self, descendants and
  the root.
- Branches never in `notes`; a shown branch appears; the tag list follows.
- Crypt barrier: `moveNoteToSpace` and `bulkMoveNotes` refuse to move a first
  note into the Crypt and refuse to move any branch; `notesPlaceableInCircuit`
  never offers a Crypt note.
- Crypt safety net: a first note injected straight into the Crypt, as data
  from an older build would be, keeps every branch out of `searchableNotes`,
  `linkTargets` and the feed, and `_repairCircuits` leaves it in the Crypt.
- Archived first note: branches not searchable. Hidden folder: a shown branch
  stays out of the feed.
- Delete subtree, delete keep-slot and delete circuit produce the right members
  in one group; `deletedNoteGroups` shape; every restore rule 1 to 7 covered;
  permanent delete of a group; the 30-day purge removes a group together.
- New-note titles: the first new branch is "Note #1", the next "Note #2", and
  after "Note #1" is deleted the next new branch reuses #1. Both
  `addCircuitChild` and `addCircuitSibling` title their note, and a new branch
  is never `isEmpty`. A new Markdown branch's source is `# Note #N` plus a
  newline and `markdownTitle` of it returns "Note #N". Note and placeholder
  numbers do not affect each other. A placeholder written into as a note is
  retitled with the next "Note #N".
- Placeholder titles: the first keep-slot delete creates "Placeholder #1", a
  second creates "#2", and after #1 is removed the next reuses #1. A
  placeholder is never `isEmpty`, never in the feed, search or link targets,
  and `setCircuitShowInFeed` refuses it. A blanked placeholder title is
  restored by `_repairCircuits`.
- `fillPlaceholder` from the same circuit and from a Home note; invalid fills
  rejected.
- `placeNoteInCircuit` clears the folder and leaves the feed;
  `removeFromCircuit` moves children up.
- `_repairCircuits` fixes a missing parent, a missing root, a cycle, a branch
  with a folder, and gapped orders.
- `deleteNote` on a branch with children leaves a titled placeholder; on a
  root it deletes the circuit.
- Persistence: build a circuit, `flushNow`, reload in a fresh AppState, same
  structure. Plus a round trip through the FFI SQLite store.

### Phase 2: Layout engine (no UI)
- [x] `lib/services/circuit_layout.dart` with all three modes (section 7).
- [x] `test/circuit_layout_test.dart` covering the section 7 test list
      (20 tests; four shapes x three modes plus collapse, determinism,
      edges and + anchor).

### Phase 3: The usable loop (first visible phase)
- [ ] "New circuit" in the pencil menu.
- [ ] Empty-note rules in both note screens (section 9).
- [ ] `fromCircuitMap` plumbing, `CircuitMapFocus`, the **+** and **map**
      buttons, the add sheet.
- [ ] `startEditing` flag, and the localized `circuitNoteTitle` formatter
      passed at every creation call (section 9).
- [ ] Map screen, left to right only: pan, zoom, fit, centre on focus, tap to
      open, **+** to add a child, highlight pulse.
- [ ] Circuit card in the feed; feed tap through `noteScreen`.
- [ ] Crypt barrier in the UI (section 6.8): `allowCrypt` on the folder picker
      at every call site, and the add-to-folder sheet exclusions. This lands
      here, not later, because this is the first phase where a circuit exists
      and could be moved.
- [ ] Strings for this phase.
- [ ] Analyzer, tests, emulator build, owner test script.

### Phase 4: Editing on the map
- [ ] Node sheet with every action; delete dialog; placeholder sheet;
      existing-note picker; pick modes.
- [ ] Layout-change animation.
- [ ] Breadcrumb chip; ⋯ menu changes; linked notes created as children.
- [ ] Analyzer, tests, emulator build, owner test script.

### Phase 5: Layout modes
- [ ] Top-down and radial rendering, with their edge shapes and **+**
      placement.
- [ ] Layout switch, persisted per circuit.
- [ ] Analyzer, tests, emulator build, owner test script.

### Phase 6: Everywhere else
- [ ] Search subtitle and icon; Recently Deleted groups; Home quick actions
      and multi-select rules; "In {circuit}" chip on shown branches.
- [ ] Seed circuit and its test; README section; string audit.
- [ ] Analyzer, tests, emulator build, full owner test script.

### Phase 7: Optional polish
- [ ] Share a circuit as a Markdown outline and as a PDF: the first note as H1,
      each branch as a heading by depth, bullets past H6, reusing
      `NotePdf.fromMarkdown`.
- [ ] Remember zoom and position per circuit (settings map, `readerPositions`
      pattern).
- [ ] Collapse and expand branches; the layout already supports `collapsed`.
- [ ] Skip building off-screen nodes for very large circuits.
- [ ] Drag a node onto another to re-parent it.

---

## 13. Verification and handoff

After every phase:

```bash
flutter gen-l10n        # only when app_en.arb changed
flutter analyze --no-pub
flutter test --no-pub
```

After every visible phase, install on the **braim_test emulator only**, never
the owner's phone:

```bash
flutter build apk --debug
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

- Never use `flutter install`. It once installed a stale build, uninstalled the
  app first, and wiped the emulator's data.
- Do not drive the emulator with adb taps or screenshots; it burns usage.
  Instead hand the owner a numbered script: what to open, what to tap, what
  should happen.
- The final script must cover at least: create a circuit; add branches from the
  note's **+** and from the map's **+**, and confirm they read "Note #1",
  "Note #2" and open ready to type; add a Markdown branch, back out without
  writing, and confirm it survives; pan, zoom and fit; open a branch and
  come back to the map; switch all three layouts; rename, recolour, reorder,
  indent, outdent and move a branch; delete with both choices, check the
  placeholder reads "Placeholder #1", then fill it; place an existing note;
  show a branch in the Home feed; restore from Recently Deleted; confirm the
  Crypt is not offered when moving a circuit to a folder, and that a circuit
  cannot be added from inside the Crypt; relaunch the app and confirm
  everything persisted.

---

## 14. Pitfalls

- **Empty-note deletion** in both note screens deletes branches and orphans
  their children unless the section 9 rules are in place.
- **`deleteNote` has many callers** (editor menu, Home quick actions,
  multi-select). Without the section 6.7 routing, any of them can orphan
  branches.
- **Crypt paths.** Circuits are barred from the Crypt, but three paths can
  put a note there: the folder picker, the add-to-folder sheet opened inside
  the Crypt, and the note screens, which set `spaceId` on the note directly
  before saving. Close all three for circuit notes (section 6.8).
- **Crypt safety net.** A branch carries no folder of its own. Any predicate
  that checks `n.spaceId` instead of the effective folder would leak a Crypt
  circuit's branches if one ever existed. Keep the effective-folder check and
  its test even though the UI forbids the case.
- **Numbered titles are only a first line of defence.** A user can clear a
  title, so the section 9 rules must still ship. Generate titles through
  `_nextNumberedTitle` (6.2); never parse numbers out of existing titles.
- **Markdown notes ignore the title field.** The Markdown screen rebuilds the
  title from the source's first heading and deletes a note with an empty
  source. A Markdown branch created with only a `title` loses it on the first
  save; always seed the source with the `# Note #N` heading.
- **`isNew` is not "start editing".** It also controls cleanup and the close
  animation. Use the separate `startEditing` flag (section 9).
- **`_isFeedNote` is shared** by the feed, tags, pins and search. Search must
  switch to `_isSearchableNote`, or circuit notes vanish from search.
- **Quadratic predicates.** Resolving roots with `noteById` inside feed filters
  is O(n^2). Use the id index.
- **Stale index.** A method that adds notes and then queries in the same call
  must refresh the index or read `_notes` directly.
- **Copied notes.** A copied `Note` handed to an editor will overwrite map
  changes on its next `upsertNote`.
- **Stack growth.** Without the `fromCircuitMap` contract, map and note screens
  pile up on the navigator.
- **JSON drift.** Writing default values in `toJson` rewrites every SQLite row
  on the next save and breaks equality tests.
- **`updatedAt`.** Bumping it on structural changes makes "Modified"
  meaningless and reorders date-sorted views.
- **Seed test.** The sample-data test asserts exact counts for folders, cards
  and books. A circuit only adds notes; keep the others unchanged.
- **Deprecated Matrix4 calls** break the clean-analyzer rule on Flutter 3.41.

---

## 15. Open decisions (defaults chosen; confirm with the owner)

| Question | Default in this guide |
|---|---|
| A `[[link]]` that creates a new note from inside a circuit note | Created as a child of that note, so it stays in the circuit |
| Home multi-select holding branches shown in the feed | Bulk delete, archive and move skip them, with a snackbar; they are managed on the map |
| Remove from circuit on a branch with children | Its children move up to its parent |
| Radial start angle | Top, clockwise |
| First note as a Markdown note | Not in v1; the first note is rich, branches can be either |
| Circuits inside circuits | Not in v1 |
| Moving a branch to another circuit | Not in v1; remove it, then place it |
| An archived circuit's branches in search | Hidden; the first note appears under Archived results |
| Circuit icon | Material's `account_tree` until the owner supplies a custom mark, which would be drawn like `BraimLogo` |
| Circuits in the Crypt | **Decided by the owner:** not allowed. See sections 1 and 6.8 |
| Placeholder naming | **Decided by the owner:** "Placeholder #1", "#2" and so on, so a placeholder is never an empty note |
| Titles for new notes in a circuit | **Decided by the owner:** "Note #1", "Note #2" and so on, from every creation path (sections 1 and 6.2) |
| Radial ring spacing vs the default `ringGap` (120) | **Implemented (Phase 2), confirm:** the default `ringGap` (120) is smaller than the node diagonal + `breadthGap` (~213), which section 7 says rings must clear, so a parent and its single child stacked on one radius would overlap. The layout uses `max(ringGap, nodeDiagonal + breadthGap)` for the actual ring spacing, which keeps section 7's no-overlap guarantee. Nodes only ever sit further apart, never closer. |

---

## 16. Out of scope for v1

Circuits inside circuits, circuits in the Crypt, moving between circuits in one
step, drag-and-drop editing (Phase 7 only), shared or synced circuits, and
custom icon artwork.
