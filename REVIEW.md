# Braim deep review

Snapshot: `main` at `af51597` (clean tree), reviewed 2026-10-12/13. Read-only review: no source file was changed.

## 1. Verdict

**Not done.** 15 High and 36 Medium findings survived adversarial verification. There are no Blockers.
The High ones cluster in five places:

- the focus timer (a crash on Android 12 and lower, and DND left on);
- unsaved text in the Markdown editor when Android kills the app;
- note screens opened for reading that either don't save an action or write stale text over newer text;
- reminders that outlive the thing they belong to;
- Crypt items that leak out or become unreachable.

The rest are spread across reflex maths, exports, books and Braim Web. These are the results of one review pass, so they are a sample, not a census (see section 9).

| Severity | Confirmed | Plausible | Total |
|---|---|---|---|
| Blocker | 0 | 0 | 0 |
| High | 14 | 1 | 15 |
| Medium | 31 | 5 | 36 |
| Low (backlog) | 49 | 4 | 53 |
| Needs-info | | | 1 |
| Refuted | | | 1 (+1 partly) |

## Fix status (2026-10-15)

All 15 High and 35 of the 36 Medium findings are fixed, each with a regression test written first and
seen to fail (except where the bug can't be reproduced on this machine, noted below). The fixes were
then re-reviewed on their own, in a fresh context. That found 4 Medium and 4 Low problems in the
fixes, all now fixed with tests too (R1-01 to R1-08 below). Nothing is committed.

| Oracle | Before | After |
|---|---|---|
| `flutter analyze` | No issues | No issues |
| `flutter test` | 492 passed | 558 passed (16 new test files) |
| `flutter build apk --debug` | built | built (Kotlin changes compile) |

**Fixed, by root cause:** RC1 to RC15 and U6-03, as planned in section 5. Choices made where the
report left one open:

- **Crypt archive (U11-02).** Archive is no longer offered inside the Crypt. Anything already archived
  there is listed in the Crypt again, where Unarchive works.
- **Crypt in Recently Deleted (U11-03).** Crypt items sit behind one "N items from the Crypt" row that
  asks for the Crypt unlock. Empty leaves them alone until then.
- **Crypt reminders (U13-07).** A reminder for a Crypt note shows only "Reminder / Open Braim to see
  it."
- **A link already in the Crypt (U11-04, U3-02).** Saving it again, on the phone or on Braim Web,
  makes a new spark and leaves the Crypt copy untouched. The Braim Web test that pinned the old reply
  was updated.
- **"Once" tasks (U10-08).** They still remind daily until ticked, then stop. Unticking re-arms them.
- **Folder tag filter (U11-05).** The tag picked in a folder's sheet filters that folder (it is shared
  with Home), with the same clearable chip Home shows. It is never applied inside the Crypt.
- **Reflex streaks (U9-05).** They use the heatmap's count. For checklist reflexes, a day without a
  tick breaks the run.
- **Book pages (U8-01).** Long-press Delete now goes to Recently Deleted, like deleting from the
  editor.
- **Focus timer (U7-01, U12-02, U7-04).**
  - The notification button goes to a private receiver, and the androidx receiver that crashed is
    gone.
  - An Android alarm ends the session's Do Not Disturb even if Braim is frozen.
  - Do Not Disturb puts back exactly what was on before and never touches a DND Braim didn't set.
- **Storage (U2-01 to U2-05, U2-07, R1-01).**
  - Unreadable data files are copied aside before anything replaces them.
  - A missed database save, or a restore, marks the JSON as the newer copy.
  - A database row that can't be read is left in the database untouched while the rest loads.
  - Restore streams from the file.
  - Zip entries inflate in capped chunks, and entries flagged as symlinks are skipped (R1-02).
- **Dates.** Calendar days come from `lib/services/calendar_days.dart`, and the app notices a new day
  (a midnight timer and on resume).

**Verified only by building, not by a test** (native, or this machine has no daylight saving):

- U7-01: the focus notification's Play/Pause, on Android 12 or lower.
- U12-02: the session-end alarm with the phone asleep.
- U11-06: sharing a .txt file to Braim.
- U11-08: no second import after Android restores Braim from Recents.
- The DST fixes: the helpers are tested, but not in a zone with clock changes.

These need the manual checks listed with the hand-off.

**Not fixed:**

- **U12-09 (Medium).** Settings › Save to device still hands the whole zip to file_picker in memory.
  Fixing it needs a native streaming save; Send a copy (the share sheet) is the route for large
  libraries meanwhile.
- **U4-01 (remainder).** In a block edited on Braim Web, a link with a custom scheme (an app link) is
  still dropped by the Quill editor's own link rules. Untouched blocks now keep every link, and `tel:`
  and `sms:` survive edits.
- **Suspicions from the re-review** (unconfirmed; worth a look):
  - a start racing a pause's DND restore;
  - the session-end alarm doesn't survive a reboot;
  - a save between a restore's file write and the reload.
- **The Low backlog in section 7.** Fixed incidentally were U1-08 (reminders), U2-06, U3-03, U5-06,
  U7-05/U9-11/U10-09, U7-15/U12-05, U8-13, U10-03, U10-04, U11-07, U11-10, U12-03, U12-06 and part of
  U8-04.

**Convergence:** done still needs a fresh blind pass over the whole fixed code (section 9). Only the
diff-scoped re-review has run.

## 2. Baseline oracles

| Oracle | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 492 tests, all passed |
| Build | Not rebuilt for this review (last debug build succeeded earlier this session) |

No test or analyzer failure exists to report. Every finding below comes from reading code and tracing calls. Some were also reproduced with throwaway scripts (marked "script").

## 3. Intent sheet and assumptions

Intent was taken from README.md (the operator's handbook), `docs/circuit-feature-plan.md`, `docs/braim-web-plan.md`, `docs/sqlite-migration-plan.md`, the tests, and doc comments. The invariants these findings are measured against:

- Every AppState mutation persists (`_persist`) and notifies. Leaving an editor or killing the app must not drop the user's text.
- Crypt content never shows outside the unlocked Crypt (feeds, search, Braim Web, other screens). Crypt controls access only; it doesn't encrypt.
- Recently Deleted keeps items 30 days and restores exactly what was deleted.
- An image file is never deleted while a live or trashed item, or a saved chapter version, still points at it.
- If the database fails, the app falls back to JSON so no data is lost. A restore must survive a crash before the database catches up.
- Reminders exist only for items that exist and are live.
- Braim Web serves notes, sparks, circuits and books only, and keeps one editor per note (the lease).
- Files shared in (.braim, .md, .txt, zips) are untrusted.

Assumptions:

- The owner's device is in IST, which has no daylight saving. The DST findings don't affect the owner but do affect Play users in Europe, the Americas and Australia.
- "Archive" inside the Crypt was meant to work. Nothing says it should hide items for good.

## 4. Findings table (Medium and above)

IDs are the reviewer IDs (U1 to U13 are the review units). Duplicates found by several reviewers are listed once, with the other IDs in brackets.

| ID | Sev | Status | Location | Finding |
|---|---|---|---|---|
| U7-01 [U12-01] | High | Confirmed | FocusMedia.kt:144-150, AndroidManifest.xml:88-94 | Tapping Pause/Play on the focus notification crashes the app on Android 12 and lower |
| U12-02 | High | Plausible | pomodoro_controller.dart:250-290 | When the phone sleeps or freezes Braim, a focus session never ends and DND stays on |
| U13-04 [U5-04] | High | Confirmed | markdown_note_screen.dart (no save timer or lifecycle hook) | Markdown editor saves only on Done/back, so a background kill loses everything typed |
| U13-01 [U6-01] | High | Confirmed | note_editor_screen.dart:405-416, 650-655 | Archive from the ⋯ menu of a note being read is never saved |
| U13-02 [U5-01] | High | Confirmed | markdown_note_screen.dart:306-327, 169-198 | In reading mode the map and + buttons write the text from when the screen opened over newer text |
| U9-01 [U1-02] | High | Confirmed | app_state.dart:4240-4245 | Deleting a reflex leaves its daily reminders firing forever |
| U13-03 [U7-03, U12-10] | High | Confirmed | app_state.dart:3131-3153, 397-401 | After a restore, reminders of the old library still fire, some forever |
| U11-02 | High | Confirmed | app_state.dart:1036-1067 | Archiving an item inside the Crypt makes it unreachable from every screen |
| U11-04 [U3-02, U13-06, U1-06] | High | Confirmed | app_state.dart:3393-3405 | Saving a link that's already in the Crypt moves the Crypt card out into a normal folder |
| U2-01 | High | Confirmed (trace) | app_state.dart:475-497, storage_service.dart:89-96, 195-225 | If both JSON files are unreadable on import, the next two saves delete the original library |
| U9-03 | High | Confirmed | impulse.dart:427-431 | A long-term goal is marked complete for good once each daily reminder is ticked on any day |
| U9-06 | High | Confirmed | app_state.dart:3845-3866 | Analytics counts days before a reflex existed as missed |
| U7-02 | High | Confirmed (script) | note_markdown.dart:95-110 | Share as plain text or .docx joins separate lines into one ("Milk Eggs Bread") |
| U11-01 | High | Confirmed | home_screen.dart:196-209, app_state.dart:175-180 | When the filtered tag disappears, Home looks empty and the filter can't be cleared |
| U8-01 | High | Confirmed | book_screen.dart:789-804, app_state.dart:3356-3365 | Long-press "Delete page" erases a chapter at once, with no confirm and no Recently Deleted |
| U7-04 [U12-04] | Med | Plausible | dnd_service.dart:66-80 | With timer DND set to Off, the timer still switches off the user's own DND |
| U6-07 | Med | Confirmed | note_editor_screen.dart:536, root_shell.dart:150-154 | Rich editor: the last ≤3 s of typing is lost if the app is killed after Home |
| U8-03 | Med | Confirmed | book_screen.dart:1270-1319 | A chapter title typed on the Contents screen is dropped by the back gesture |
| U5-02 | Med | Confirmed | markdown_note_screen.dart:188-190, 251-260 | Emptying a Markdown note and tapping Done trashes it, but the screen stays and later edits go into the trashed note |
| U13-11 [U6-06] | Med | Confirmed | note_editor_screen.dart:215-223, markdown_note_screen.dart:262-271 | A note deleted on Braim Web while open on the phone can still be edited; edits land in the trash |
| U6-04 [U8-06] | Med | Confirmed | note_editor_screen.dart:640-643, app_state.dart:3337-3346 | Book Notes "+" then back leaves a blank note forever |
| U9-02 | Med | Confirmed | app_state.dart:4260-4267 | Archiving a reflex leaves its reminders armed |
| U10-08 | Med | Confirmed | app_state.dart:4473-4486 | A "Once" task with a start time reminds every day forever, even after it's ticked |
| U13-14 [U1-03, U7-09] | Med | Confirmed | app_state.dart:2453-2549 | Restoring a note from Recently Deleted doesn't bring its reminder back until the next cold start |
| U11-03 | Med | Confirmed | app_state.dart:1052-1054, 2429-2433 | Deleted Crypt notes and sparks show in Recently Deleted without unlocking |
| U13-07 | Med | Confirmed | notification_service.dart:530-545 | A Crypt note's reminder shows its title and text on the lock screen |
| U2-02 [U1-04] | Med | Confirmed | app_state.dart:4730-4732 | A failed SQLite save is ignored, so the next launch can read a stale library over newer JSON |
| U2-03 [U13-05, U12-08] | Med | Confirmed | backup_service.dart:233-240 | A restore doesn't flag the JSON as newer, so a crash right after can quietly undo the restore |
| U2-04 [U1-05] | Med | Confirmed | app_state.dart:491-492, main.dart:132 | One corrupt database row leaves the app on its loading spinner forever |
| U2-05 [U12-07] | Med | Plausible | app_state.dart:406-438, backup_service.dart:49-54 | Two pauses in the same minute can write a corrupt auto-backup and prune a good one |
| U2-07 [U12-09] | Med | Confirmed | backup_service.dart:209-227, settings_screen.dart:183-189 | Restore and Save to device hold the whole backup in memory; large libraries run out of memory |
| U1-01 [U6-02, U8-05, U13-13] | Med | Confirmed | app_state.dart:2836-2839, web_api.dart:640 | Removing an image deletes the file even when a saved chapter version still uses it |
| U10-05 | Med | Confirmed | journal_screen.dart:60-63 | After midnight with Braim still in memory, the journal still files entries and ticks on yesterday |
| U9-08 | Med | Plausible | reflexes_screen.dart:1082, 2216 | Same rollover problem on reflex screens: the first tick after midnight lands on yesterday |
| U10-01 | Med | Confirmed | journal_screen.dart:454-461 | DST zones: week strip pages across a clock change show wrong weekdays and lose the highlight |
| U10-02 | Med | Confirmed | journal_screen.dart:96 | DST zones: picking a date across a clock change scrolls to the wrong week |
| U9-04 | Med | Confirmed | reflexes_screen.dart:1308-1325 and others | DST zones: heatmaps drop today's cell or shift by a day; streaks skip or double a day |
| U9-05 | Med | Confirmed | app_state.dart:4341-4384 | Streak ignores per-thread weekdays and one-time tasks, so it contradicts the heatmap |
| U9-07 | Med | Confirmed | impulse_analytics_screen.dart:75 | "Current streak" ignores the chosen reflex and can exceed "Best streak" |
| U10-07 | Med | Confirmed | app_state.dart:4293-4309 | Moving a task out of a long-term goal silently does nothing |
| U4-01 | Med | Confirmed | web_api.dart:42-48, web_html.dart:71-88 | Editing a note on Braim Web strips `tel:`, `sms:` and custom-scheme links from the whole note |
| U4-02 | Med | Confirmed (script) | assets/web/editor.js:379-428 | Text typed on the web while photos upload is lost on the reload |
| U3-01 | Med | Plausible | web_server.dart:151-166, web_security.dart:55-62 | A carrier's 10.x mobile-data address counts as Wi-Fi; Braim Web starts with Wi-Fi off |
| U11-06 [U7-08, U13-08] | Med | Confirmed | ShareActivity.kt:22-26, AndroidManifest.xml:107-111 | Sharing a .txt file to Braim does nothing ("No link found") |
| U11-08 [U7-07] | Med | Plausible | MainActivity.kt:25-29 | A share that cold-started Braim is imported again after the process is restored |
| U8-07 | Med | Confirmed (script) | book_export.dart:230-235 | Book Markdown export merges every chapter's lines into one paragraph |
| U11-05 | Med | Confirmed | space_detail_screen.dart:268, app_state.dart:1064-1067 | A folder's "Filter by tag" doesn't filter the folder; it silently filters Home |
| U8-02 | Med | Confirmed | book_screen.dart:1235-1249 | Reordering on the Contents screen moves the wrong page once Contents isn't first |
| U5-03 | Med | Confirmed (script) | circuit_file.dart:273-286, 368-377 | A 408 KB .braim zip bomb pushed memory to about 1 GB before being rejected |
| U7-06 | Med | Confirmed | link_preview_service.dart:100-106, 205-211 | Link previews download the whole body with no size cap; a timeout doesn't stop the download |
| U6-03 | Med | Confirmed (script) | note_body_editor.dart:576-583, 664-681 | Removing a photo below a checklist turns the last item into plain text (loses its tick) |

## 5. Detail by root cause

Fix order: RC1 and RC2 first (data loss), then RC3 (reminders), RC4 (Crypt), RC5 (crash). The rest are independent of each other.

### RC1. Text that never reaches storage (U13-04, U6-07, U8-03, U10-06, U8-11)

Both note editors keep text in their controllers and copy it into the Note only on Done, back, or (rich editor only) a 3-second timer. Neither screen listens for the app being paused. `root_shell` flushes AppState on pause (`root_shell.dart:144-162`), but text still in a controller isn't in AppState yet. Android routinely kills a backgrounded app.

- **U13-04 (High).** The Markdown editor has no timer and no lifecycle hook (`grep Timer|WidgetsBindingObserver` finds nothing in `markdown_note_screen.dart`). Type in a Markdown note, press Home, and the OS kills the app: everything since the editor opened is lost.
- **U6-07 (Medium).** The rich editor's `Timer.periodic(3 s)` (`note_editor_screen.dart:536`) leaves a window of up to 3 s. A further 380 ms delay in `_persistLater` adds to it.
- **U8-03 (Medium).** A Contents-screen title is committed only on submit or tap-outside (`book_screen.dart:1291-1319`); the back gesture does neither.
- U10-06 and U8-11 (Low): the task sheet title and the reader position are kept only in memory until close or dispose.

**Fix:** give `MarkdownNoteScreen` and `NoteEditorScreen` an `AppLifecycleListener`. On `inactive`/`paused`, run the existing collect-and-save (`_save()` while editing / `_autosaveTick()`), then `appState.flushNow()`. Add a debounced save on `_ctrl` changes in the Markdown editor, keeping the delete-if-empty rule for leave only. For the Contents rows, commit on focus loss and in `deactivate()` when the text changed.
**Blast radius:** the two editor screens; `phone_lease_test.dart` and the circuit navigation tests open them. The empty-note delete must stay on leave only, or a pause would delete a note the user is still writing.
**Regression test:** type into each editor, dispatch `AppLifecycleState.paused`, and assert `state.noteById(id)` holds the text without advancing time.

### RC2. Reading mode treated as editing, and the reverse (U13-01, U13-02, U5-02, U13-11, U6-04, U6-05, U6-09, U8-04)

Saved notes open read-only (`_editing = widget.isNew || widget.startEditing`, `note_editor_screen.dart:523`). Several actions were written for the editing state:

- **U13-01 (High).** ⋯ › Archive does `_note.archived = !_note.archived; _close();`, and `_close` in read mode only pops (`:652-655`). Nothing calls `_persist`, so the feed (cached on `_rev`) still shows the note and a kill loses the change. `_note` is the same object AppState holds.
- **U13-02 (High).** `_circuitMap` and `_circuitAdd` call `_save()` unconditionally (`markdown_note_screen.dart:306-314`). `_save` writes `_ctrl.text`, which is refreshed only in `_startEditing` and `_afterMap`. This undoes a Braim Web edit, or a rename made through a linked map, and bumps `updatedAt`.
- **U5-02 (Medium).** Emptying an existing Markdown note and tapping Done calls `deleteNote` but keeps the screen open on the old text. A later pencil › edit › Done calls `upsertNote`, which keeps `deletedAt`, so the note is purged after 30 days.
- **U13-11 (Medium).** If Braim Web deletes a note the phone is reading, the pencil still starts editing (`_startEditing` checks only the lease), and saves go into the trashed note. Only `_afterMap` checks `deletedAt`.
- **U6-04 (Medium).** `addBookNote` inserts and saves the note before opening it with `isNew: true`. `_persistNow` deletes an emptied note only when `!isNew || _persisted`, so the blank note stays.
- Low: U6-05 (✓ on an emptied note keeps it); U6-09 and U8-04 (read-mode link, map and + buttons, and phone book edits, bump `updatedAt` while a browser holds the lease, forcing a web 409).

**Fix:**
- Archive: call `state.setNoteArchived(_note.id, !_note.archived)` before popping.
- In `_circuitMap`/`_circuitAdd`, save only `if (_editing)`.
- In `_done`, pop when `_save` deleted the note.
- In `_startEditing` (both screens), refuse and pop with a snackbar when `noteById(id)?.deletedAt != null`.
- In `_persistNow`, also clean up when `isNew` and the note is already in the library (`permanentlyDeleteNote` for an untouched draft).
- Guard read-mode `upsertNote` calls with `if (_editing)`.

**Blast radius:** note_editor_screen, markdown_note_screen. Tests: `phone_lease_test`, `circuit_navigation_test`, `markdown_paste_test`.
**Regression tests:**
- Archive from read mode leaves the note in `archivedNotes`.
- The browser changes a source while the phone reads; the phone taps the map; the source is unchanged.
- Book + then back leaves `bookNotes` empty.

### RC3. Reminders outlive their items (U9-01, U13-03, U9-02, U10-08, U13-14, U1-08, U13-07)

`rescheduleReminders()` (`app_state.dart:3131-3153`) only arms. Nothing ever cancels an alarm whose item has gone, and the reflex alarms repeat (`matchDateTimeComponents`).

- **U9-01 (High).** `deleteImpulse` only removes the reflex from the list. `deleteThread`/`deleteSection` do cancel, which shows the intent. Once the thread ids are gone, the alarm can't be cancelled from the app.
- **U13-03 (High).** A restore (`_applyData` then `rescheduleReminders`) arms the new library's reminders but leaves the old library's alarms in place. `clearAll` (U1-08) has the same gap.
- U9-02 (Medium): archiving a reflex keeps its alarms, and `rescheduleReminders` skips archived reflexes without cancelling them.
- U10-08 (Medium): a "Once" task with a start time is scheduled as a daily repeat (`weekdays: {}`), and ticking it never cancels.
- U13-14 (Medium): restoring a note from Recently Deleted doesn't call `syncNote`.
- U13-07 (Medium): `syncNote` puts the note's title and 120 characters of text into the notification, including for Crypt notes.

**Fix:** add `NotificationService.reconcile(Set<int> expectedIds)`. It reads `pendingNotificationRequests()` and cancels anything not expected, except focus and journal ids. Call it at the end of `rescheduleReminders`. Call `rescheduleReminders()` after `deleteImpulse`, `setImpulseArchived`, `clearAll` and `restoreTrashGroup` (cheap; it already runs at launch). Schedule "once" threads without `matchDateTimeComponents`, and skip them once `doneDays` is non-empty. In `syncNote`, use a generic title and body when the note's folder is the Crypt.
**Blast radius:** notification_service; app_state reflex, trash and restore methods. Tests that fake notifications: `reminder_hint_test`, `app_state_test` reflex group.
**Regression test:** with a fake plugin holding ids {A, B}, delete a reflex and restore a library without B. Expect `cancel` for both, and nothing else cancelled.

### RC4. Crypt boundary (U11-02, U11-04, U11-03, U13-07)

- **U11-02 (High).** `archivedNotes`/`archivedCards` exclude the Crypt (`app_state.dart:1036-1050`), while `notesForSpace` excludes archived items (`:1064-1067`). The Crypt's long-press sheet still offers Archive (`space_detail_screen.dart:69-99`). An archived Crypt item then appears nowhere (folder, Archive, search, web) and can't be unarchived.
- **U11-04 (High).** `addCardFromUrl` reuses any live card with the same URL, Crypt included, and sets `card.spaceId = spaceId` (`:3397-3401`). Re-sharing a Crypt link into a folder, or from the share popup, moves the Crypt card, private note included, into the open: Sparks, search and Braim Web. From Braim Web the same path un-archives the Crypt card and answers `{}` instead of `{id}`, which reveals that the link is in the Crypt.
- U11-03 (Medium): `deletedNoteGroups`/`deletedCards` don't filter the Crypt, so Recently Deleted shows Crypt titles, text and photos without unlocking.
- U13-07: see RC3.

**Fix:**
- In `addCardFromUrl`, ignore cards whose `spaceId == kCryptSpaceId` when looking for a duplicate, so a new card is created.
- Don't offer Archive for Crypt items, or list archived Crypt items inside the unlocked Crypt.
- Either leave Crypt items out of Recently Deleted (giving the Crypt its own trash view after unlock) or ask for the unlock before showing them.

**Blast radius:** app_state card and archive getters, space_detail_screen, recently_deleted_screen. Tests: `web_editing_test` (pins the `{}` reply), `web_visibility_test`.
**Regression test:** a Crypt card for URL X; `addCardFromUrl(X, spaceId: F)` leaves it in the Crypt and creates a new card in F.

### RC5. Focus timer and Do Not Disturb (U7-01, U12-02, U7-04, U12-03, U12-06, U7-15)

- **U7-01 (High).** The notification's Play/Pause uses `MediaButtonReceiver.buildMediaButtonPendingIntent` (`FocusMedia.kt:147`). The manifest declares the androidx `MediaButtonReceiver` but no service handling `MEDIA_BUTTON` and no `MediaBrowserService`. androidx's `onReceive` then throws `IllegalStateException("Could not find any Service that handles android.intent.action.MEDIA_BUTTON…")`. On Android 12 and lower the tap goes through this receiver and the process dies. The receiver is `exported="true"`, so any app can trigger the same crash on any version.
- **U12-02 (High, Plausible).** The phase end and the DND restore run only in an in-process `Timer.periodic` (`pomodoro_controller.dart:250-290`). There is no alarm and no foreground service. With the screen off, Doze or the cached-app freezer stops the timer, so DND stays on long after the session ends.
- U7-04 (Medium, Plausible): `apply(DndMode.off)` calls `restore()`, which always sets FILTER_ALL (`dnd_service.dart:66-80`). That switches off a DND the user set themselves on Android 14 and lower. The previous filter is never saved, though a native `getFilter` exists.
- Low: U12-03 (pause after a long freeze replays elapsed phases), U12-06 (settings stay locked after a session completes), U7-15 (stale focus notification after a kill).

**Fix:**
- Point the action at a small app-private receiver (`exported="false"`) that calls the live session's transport controls, or add a `MEDIA_BUTTON` service that calls `MediaButtonReceiver.handleIntent`.
- Arm an exact `AlarmManager` broadcast at the session end that restores DND and clears notification 900001; cancel it on pause and reset.
- Make `apply(off)` a no-op, and save and restore the previous filter.

**Blast radius:** FocusMedia.kt, AndroidManifest, MainActivity channel, pomodoro_controller, dnd_service. No Dart tests cover the native side; verify manually on an API 30 and an API 34 emulator.

### RC6. Storage durability (U2-01, U2-02, U2-03, U2-04, U2-05, U2-07, U2-06, U2-08)

- **U2-01 (High, rare trigger).** Suppose `keepy_data.json` and its `.bak` both exist but fail to parse (a torn write, or a field a newer build wrote). Then `loadForImport` throws (good), but `init` continues with `loadLegacy()`, which returns `AppData.empty()`. With the DB not primary, `_flush` writes JSON on every save. Save 1 rotates the unreadable main file to `.bak`, deleting the old `.bak`. Save 2 deletes that `.bak` too (`storage_service.dart:195-225`). The original library is gone.
- U2-02: `_flush` discards `syncFromAppData`'s `false` result (`app_state.dart:4730-4732`), so no JSON-ahead flag is raised. The FTS inserts share the entity transaction (`db_store.dart:177-189`), so a damaged `search_fts` table fails every save. The next launch reads the stale DB, and its first pause checkpoint overwrites the newer JSON.
- U2-03: `restoreFromZipBytes` writes the JSON but never calls `markJsonAhead()`. A kill before `init(restored: true)` finishes syncing reverts the restore on the next launch.
- U2-04: `readAppData()` has no try. One malformed row body throws out of the unawaited `init()`, and the app spins forever.
- U2-05: `maybeBackupOnPause` has no in-flight guard, and temp zips are named to the minute.
- U2-07: restore and Save to device hold the whole zip (and every inflated entry) in memory.
- Low: U2-06 (restore doesn't rewrite book covers, feed backgrounds or chapter-history image paths; only matters when the documents path differs, which on Android user 0 it doesn't), U2-08 ("skip unchanged" resets every launch).

**Fix:**
- When a store file exists but neither copy parses, copy both aside (`keepy_data.unreadable-<ts>.json`) before returning empty.
- `markJsonAhead()` whenever a sync returns false, and before the restore's JSON save.
- Wrap `readAppData()` and fall back to JSON (treating the DB as not primary for that launch).
- Add a `_backupInFlight` flag and unique temp names.
- Restore through `decodeStream`/`InputFileStream`, writing each entry with a size cap.

**Blast radius:** app_state init, flush and backup; storage_service; backup_service; db_store. Tests: `db_migrator_test`, `db_store_test`, `backup_service_test`, `app_state_test` (persistence group).
**Regression tests:**
- Write `{not json` to both files, init, persist twice; the original bytes still exist on disk.
- A DbStore stub whose sync returns false, then `flushNow`; a new AppState sees the edit.

### RC7. Image lifetime (U1-01; Low: U5-05, U11-11, U12-12, U8-10)

`refreshAfterImageRemoval` and the purge paths call `StorageService.deleteImage` with no reference check (`app_state.dart:2836-2839`; also `web_api.dart:640`). Chapter versions copy image blocks (`_copyBlocks`), and a version is captured whenever a chapter opens. So removing a photo from a chapter breaks it in the version meant to undo that removal. The reverse problem also exists: replaced folder covers, feed backgrounds and book covers are never deleted. They pile up in `images/` and in every backup.

**Fix:** one `_deleteImageIfUnreferenced(path)` that scans note blocks, `history[*].blocks`, cards, book covers, folder thumbnails and feed backgrounds. Use it everywhere a file is deleted, and when a cover or background is replaced.
**Regression test:** snapshot a chapter with a photo, remove the photo, restore the version; the file exists.

### RC8. Dates: day rollover and daylight saving (U10-05, U9-08, U10-01, U10-02, U9-04; Low: U10-03, U10-04, U8-13, U9-11/U10-09/U7-05)

- **Rollover.** `JournalScreen._selected` is set only in `initState` (`journal_screen.dart:60-63`), and the reflex screens capture `DateTime.now()` at build. Nothing notifies when the day changes (`AppState.resume()` only drains the share inbox), so after midnight the kept-alive screens file to yesterday.
- **DST.** Days are stepped with `Duration(days: n)` on local midnights. That is 24 hours, so across a clock change the result lands on 23:00 or 01:00. That breaks `==` against midnights and the weekday labels. Notification "next occurrence" maths does the same on `TZDateTime`.

**Fix:**
- Add two helpers, `addDays(d, n) => DateTime(d.year, d.month, d.day + n)` and `daysBetween(a, b)` computed on `DateTime.utc` dates, and use them everywhere `Duration(days:` touches a calendar date.
- In `notification_service`, build `tz.TZDateTime(tz.local, y, m, d + k, h, min)`.
- On resume, notify listeners when `todayKey` changed, and have `JournalScreen` roll `_selected` forward if it was still on the old today.

**Blast radius:** journal_screen, journal_year_screen, reflexes_screen, impulse_analytics_screen, app_state streak/history, notification_service, chapter_history_screen. Tests: `day_lines_test`, the reflex tests in `app_state_test`.

### RC9. Reflex counting (U9-03, U9-06, U9-05, U9-07, U10-07; Low: U9-09, U9-10)

Each figure picks its own set of threads and its own rule for "done":

- **U9-03 (High).** `isComplete` treats a long-term goal's flat daily reminders as done-for-good (`threads.every((t) => t.doneDays.isNotEmpty)`), while `threadDone` treats long-term threads as per-day. Ticking every reminder once moves the goal to Done at 100% for good.
- **U9-06 (High).** `scopeTallyOn` never checks `consistencyStart` or the deadline, so a reflex created today shows 1 of 7 (14%) on 1W and 1 of 365 on 1Y.
- U9-05/U9-07 (Medium): `streakFor` ignores per-thread weekdays and once-tasks. "Current streak" uses the unscoped `activityStreak()` while "Best" is scoped.
- U10-07 (Medium): `moveThread` searches only flat `threads`, so a subsection task silently stays put while the sheet closes as if it moved.

**Fix:**
- `isComplete`: add `!isLongTerm` to the automatic rule.
- `scopeTallyOn`: skip days outside `consistencyStart..deadline`.
- Base streaks on the same per-day tally as the heatmap, scoped the same way.
- `moveThread`: use `findThread`/`removeThread`.

**Blast radius:** impulse.dart, the app_state analytics block, impulse_analytics_screen. Tests: the `app_state_test` reflex group pins `isComplete` for checklists (lines 785, 909-929); keep those passing.

### RC10. Exports lose structure (U7-02, U8-07; Low: U7-10 to U7-14, U8-08, U8-09, U8-12, U8-14, U12-14, U7-17)

- **U7-02 (High).** `_compose` writes each rich line followed by one newline (`note_markdown.dart:105-108`). In Markdown that is a soft break. `markdownToPlainText` and `NoteDocx` turn soft breaks into spaces, so Share as plain text or .docx prints "Milk Eggs Bread". A plain line after a bullet is folded into the bullet.
- U8-07 (Medium): the book `.md` export has the same problem (single newlines, nothing escaped).
- Low:
  - nested list levels are dropped;
  - plain text isn't escaped ("2*3*4" becomes italic);
  - the PDF ignores an ordered list's start number and loose task boxes;
  - a nested code fence closes early, and links containing parentheses are cut short;
  - the PDF italic font is Latin-1 only;
  - ePub control characters, the charset meta, an empty spine, and a cover MIME type that doesn't match its bytes;
  - the reader's "Share as PDF" shares text;
  - find and replace can't match across formatting;
  - relative og:image URLs aren't resolved.

**Fix:** in `_compose`, end a non-list line that is followed by another line with a hard break (`\`), and put a blank line between a list and a following paragraph. Escape Markdown specials in plain runs, and indent list items by `line.indent`. Reuse the same writer for the book export.
**Blast radius:** note_markdown (also used by Markdown share, .docx, PDF, txt), book_export. Tests: `share_formats_test`, `note_markdown_test`, `markdown_paste_test`; expected strings there will change where they encode the old soft breaks.

### RC11. Feeds and folders (U11-01, U11-05; Low: U11-09, U11-10)

- **U11-01 (High).** `_activeTag` is cleared only by `setActiveTag`. When the last note with that tag is deleted, archived or untagged:
  - `notes` is empty, and Home shows the first-run empty state, which has no tag chip;
  - with no tags left, the sort sheet's tag row hides (`sort_button.dart:84-85`) and the drawer lists none, so nothing can clear the filter until a restart;
  - with other tags left, the dropdown's value isn't among its items (an assertion in debug).
- U11-05 (Medium): the folder's sort sheet sets the global `activeTag`, but `notesForSpace` ignores it. The folder doesn't change and Home is filtered behind it.

**Fix:** in the `notes` getter (or wherever `allTags` is computed), clear `_activeTag` when it's no longer in `allTags`, and show the chip in the empty branch too. Give `SpaceDetailScreen` its own tag filter.
**Regression test:** notes [A#work, B]; `setActiveTag('work')`; delete A; `activeTag` is null and `notes` contains B.

### RC12. Books (U8-01, U8-02)

- **U8-01 (High).** The long-press "Delete page" calls `deleteBookPage`, which does `_notes.removeAt(idx)` and deletes the page's images. That means no confirm and no Recently Deleted, and the chapter's version history goes with it. Deleting from inside the editor soft-deletes, which shows the intent.
- U8-02 (Medium): `ContentsScreen` maps reorder indices with `offset = all.length - pages.length`, which assumes the Contents page is first. Contents can itself be reordered (`app_state_test.dart:594` does it).

**Fix:** use `deleteNote(page.id)` (`bookPages` already filters deleted pages, and restore puts the page back). Map reorder indices by identity: `all.indexOf(pages[from])`.

### RC13. Braim Web (U4-01, U4-02, U3-01; Low: U3-03, U4-03 to U4-10)

- U4-01: `sanitizeDelta` keeps only http, https and mailto links (`safeUrl`). The editor loads every block through it and saves every block back. So one web edit strips `tel:`, `sms:` and custom-scheme links from the whole note, even though the phone accepts those schemes (`external_links.dart:7-15`). Bare-domain links (no scheme) are stripped the same way.
- U4-02 (script): a photo upload never updates the editor's `base`, then reloads with `navigating = true` (skipping the leave warning). Text typed during the upload is lost, and an autosave in between gets a false "Changed on your phone".
- U3-01 (Plausible): `isPrivateIPv4` accepts any 10.x address, and carriers commonly give mobile data one. Braim Web then starts with Wi-Fi off, shows an address the computer can't reach, and listens on the cellular interface. Pairing still guards the data.
- Low: leases survive server stop (60 s); unsaved text after a lost lease; Done/Esc dead on a read-only editor; no catch-up after an SSE reconnect; double checklist ticks; an empty failure banner; leave during an in-flight save; Esc on the boot window leaving the editor; Log out without a flush.

**Fix:**
- Allow `tel:`/`sms:` and other non-script schemes when storing a delta; keep `safeUrl` for rendering hrefs.
- In editor.js, lock the editor during uploads and save before reloading.
- In `privateAddresses()`, skip cellular interface names (rmnet, ccmni, pdp, wwan, clat).

### RC14. Share-in (U11-06, U11-08; Low: U11-07, U7-16)

- U11-06: every `text/plain` SEND goes to `ShareActivity`, which reads only `EXTRA_TEXT`. A .txt file (sent as `EXTRA_STREAM`) shows "No link found", although README 2-1 promises it becomes a note.
- U11-08 (Plausible): `MainActivity.onCreate` re-handles the original SEND intent when the activity is recreated from Recents after process death. The plugin delivers it as initial media again, so the share is imported twice.
- Low: the share popup lists archived and deleted folders; shared files are copied on the UI thread with no size cap.

**Fix:**
- In ShareActivity, forward stream shares to MainActivity (through `SharedFiles.safeCopy`).
- In `onCreate`, replace the intent with `ACTION_MAIN` when `savedInstanceState != null` or `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY` is set.
- Filter the popup's folders with `!archived && deletedAt == null`.

### RC15. Untrusted input (U5-03, U7-06; Low: U5-06)

- U5-03 (script): `circuit_file.dart` checks the zip header's declared size, then `f.content` inflates the whole entry. A 408 KB file declaring 10 bytes pushed memory from 215 MB to 1,022 MB before the check threw.
- U7-06: link previews read the whole response with no cap or content-type check, and `.timeout()` doesn't cancel the download.
- Low: an imported `fontScale` isn't clamped (Infinity or negative font sizes).

**Fix:**
- Inflate through a counting output stream that throws `tooLarge` at the limit.
- Stream previews with a 2 MB cap and skip non-HTML responses.
- Clamp `fontScale` to 0.8–1.6 on import.

### Other Medium

U6-03 (script): `_concatDeltas` drops the upper block's last newline and its line attributes when blocks merge, on photo removal and on Backspace. A checklist item, heading or quote on the last line loses its formatting. **Fix:** when the lower block is empty, just remove it; otherwise carry the upper line's attributes across, as flutter_quill's `PreserveLineStyleOnMergeRule` does.

## 6. Suspicions and questions

Questions for the owner:

- **U13-12 (Needs-info).** Phone delete, archive and move don't check a browser's edit lease. The browser locks with "Deleted on your phone", which may be the intended outcome. Should the phone refuse instead, as the web refuses under a phone lease?
- Should a paused or manually completed reflex still send reminders? (Today it does, and launch re-arms paused ones.)
- Should archived notes still remind? (Today they do.)
- Should Recently Deleted require the Crypt unlock for Crypt items, or should the Crypt have its own trash?
- Should the unlocked Crypt relock when Braim goes to the background, and should its screens be hidden from the Recents thumbnail (FLAG_SECURE)?
- Books and reflexes are deleted permanently, not sent to Recently Deleted (`app_state.dart:3368`, `4240`). Intended?
- Should Replace all take a chapter version first? (The code calls skipping it deliberate.)
- The focus timer's "phase alerts" strings are passed but `scheduleFocusNext`/`showFocusOngoing` are never called. Should phases alert?

Doc drift (confirmed):

- README 3-11 still says a notification with **Turn off** stays in the shade while Braim Web is on. The foreground service and notification were removed. The same stale text is in `braim_web_settings.dart:15` and plan §6.
- README 3-11 says "covers … stay on the phone", but live book covers are served on the shelf by design. The README wording should say that changing a cover stays on the phone.

Suspicions (traced but not confirmed; none blocks done):

- Two quick `resumed` events could drain the share inbox twice and duplicate a shared note (`storage_service.dart:246-262`, no lock).
- A pause between Settings › Restore's `flushNow` and `init` could checkpoint the old library over the restored JSON.
- Visibility is checked before `await _body` in web upload handlers and not re-checked after.
- `circuit_layout` has no cycle guard if a root ever gets a parent (no app path found that does this).
- `deleteCircuitSubtree` doesn't renumber siblings, so `circuitOrder` values can repeat.
- Imported duplicate block ids would share one editor controller.
- `importCircuit` exceptions escape `_handleShared` and drop the remaining shared files.
- Notification ids use `String.hashCode`. If a Dart SDK update changes the hash, armed reminders are orphaned.
- `tz.local` is read once per process, so a time-zone change keeps old wall times until a cold start.
- Book PDF page numbers count from the cover; the comment says they count from the first real page.
- The temp backup zips and file_picker's cached restore copy are never deleted from the cache.
- File names capped at 80 runes can exceed 255 bytes with emoji.

## 7. Low backlog (does not block done)

Grouped by root cause, one line each.

- Dates: U10-03 year-view cells shift in southern-hemisphere DST; U10-04 dueStreak/history/offset stepping; U8-13 "Today/Yesterday" across DST; U9-11/U10-09/U7-05 reminder hour off by one after a clock change until next launch.
- Reflexes: U9-09 a goal switched to Daily keeps hidden curriculum tasks in the journal; U9-10 the Reflexes header progress disagrees with the card.
- Journal: U10-06 the new-task title is lost on a kill (Plausible); U10-10 the calendar overflows during a swipe into a 6-row month.
- Editor: U6-05 ✓ on an emptied note keeps it; U6-08 the format bar acts on a disposed controller after ✓ then pencil; U6-10 a partly formatted `[[link]]` shows raw brackets in the read view.
- Circuits: U5-05 a shared image name in an imported .braim gives two notes one file; U5-06 fontScale not clamped; U5-07 a node action after Braim Web trashed the node (Plausible).
- Data: U1-08 Clear all data keeps empty books and armed reminders; U2-06 restore doesn't rewrite cover, background or history image paths; U2-08 "skip unchanged" auto-backup resets every launch.
- Images: U11-11 folder covers, U12-12 feed backgrounds and U8-10 book covers are never deleted when replaced.
- Web:
  - U3-03 leases survive server stop;
  - U4-03 text after a lost lease;
  - U4-04 Done on a read-only editor;
  - U4-05 no catch-up after reconnect;
  - U4-06 double tick;
  - U4-07 empty failure banner;
  - U4-08 leave during an in-flight save;
  - U4-09 Esc on the boot window;
  - U4-10 Log out without flush;
  - U6-09 read-mode link/map taps re-date a note a browser is editing (the text-size part was refuted);
  - U8-04 phone book edits re-date leased pages.
- Exports: U7-10 indent; U7-11 escaping; U7-12 PDF list start and loose tasks; U7-13 nested fences; U7-14 links with parentheses; U7-17 relative og:image; U8-08 PDF italic font; U8-09 ePub well-formedness; U8-12 "Share as PDF" shares text; U8-14 find across formatting; U12-14 cropped JPEG saved as .png.
- Share-in: U11-07 the share popup lists archived and deleted folders; U7-16 shared files copied on the UI thread with no cap.
- Folders: U11-09 "Add existing" hides hidden-folder items and follows the Home tag; U11-10 "New folder" from the item menu ignores the colour.
- Focus: U12-03 a pause after a long freeze replays phases (Plausible); U12-06 settings locked after a session completes; U7-15 stale focus notification after a kill (Plausible).
- UI: U12-15 the greeting's bold first line is measured without text scaling.
- Docs: the README 3-11 notification paragraph; the README 3-11 covers wording.

Refuted: U9-12 (undisposed dialog controllers). They are garbage-collected, and disposing right after `showDialog` returns would be unsafe during the exit animation. Partly refuted: U6-09's text-size part (that control exists only in edit mode).

## 8. Coverage

Reviewed in full, in 13 units plus one integration pass over module seams:

- **State and data:** `lib/state/app_state.dart`, every model, `lib/services/db/*`, storage, backup.
- **Braim Web:** all of `lib/web/*`, `assets/web/app.js`, `editor.js`, `map.js`.
- **Screens and widgets:**
  - circuits: map, sheets, layout, file;
  - both note editors and the body editor, read body, find, wiki and Markdown views;
  - books (all screens and export);
  - reflexes and analytics;
  - journal, daily day and year view;
  - root shell, home, cards, folders, archive, recently deleted, share popup, search;
  - settings, the pomodoro screen and controller, crop.
- **Services:** notification, dictionary, Markdown/PDF/DOCX export, link preview, article extractor, YouTube, DND, focus media.
- **Android:** all Kotlin and the manifest.

Not reviewed:

- `assets/web/vendor/quill.js` (third party);
- the CSS files (only checked where a finding depended on them);
- generated l10n;
- `seed_data.dart` (debug-only);
- `tool/`;
- iOS project files (Android is the primary target).

Not run: the app itself (by standing instruction, no emulator driving) and on-device instrumented tests. Native behaviours (U7-01, U12-02, U11-08) were traced through library sources and bytecode, not run.

## 9. Convergence metrics

- Passes: **1** fan-out pass (13 finder units plus 1 integration unit) and 1 adversarial verification pass (4 verifiers plus the lead reviewer's own traces). Verifiers reproduced 16 findings with throwaway Dart and Node scripts using copies of the repo's code (outside the repo).
- Raw candidates: 140. After merging duplicates: about 105. Refuted: 1, plus 1 partly.
- Overlap between units: the same root cause was found independently by 2 to 4 reviewers for:
  - the Crypt link merge (4 reviewers);
  - the restore reminders (3);
  - the restore JSON flag (3);
  - the image deletion (4);
  - the focus notification crash (2);
  - the .txt share (3);
  - the Markdown editor saves (3).

  That overlap suggests recall on these areas is reasonable. No blind replica was run, so no capture-recapture estimate of unseen bugs is possible.
- Stop condition not yet met. "Done" needs the High and Medium findings fixed, the oracles green, and a fresh blind pass over the fixed code that finds no new confirmed Medium+ findings. Up to 3 rounds are allowed, after which the remainder is reported as known risk.

Current statement: **15 confirmed or plausible High and 36 Medium findings remain after 1 pass; convergence not established.**
