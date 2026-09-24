import 'package:flutter/widgets.dart';

import '../models/note.dart';
import 'markdown_note_screen.dart';
import 'note_editor_screen.dart';

/// The screen a note should open in: a Markdown note renders in
/// [MarkdownNoteScreen]; every other note opens in the Quill [NoteEditorScreen].
///
/// Route every "open a note" call through this. A Markdown note opened in the
/// rich editor shows its raw `#`/`**` syntax and, on save, is rewritten as a
/// Quill delta — corrupting it — so the [Note.markdown] flag must be honoured
/// everywhere, not just on the Home feed.
///
/// [fromCircuitMap] flags a note opened from the circuit map, so its **+** and
/// **map** buttons pop back to the map (with a [CircuitMapFocus]) instead of
/// pushing a new one. [startEditing] opens a circuit note ready to type without
/// the empty-note cleanup that `isNew` also drives.
Widget noteScreen(
  Note note, {
  bool isNew = false,
  bool fromCircuitMap = false,
  bool startEditing = false,
}) =>
    note.markdown
        ? MarkdownNoteScreen(
            note: note,
            isNew: isNew,
            fromCircuitMap: fromCircuitMap,
            startEditing: startEditing,
          )
        : NoteEditorScreen(
            note: note,
            isNew: isNew,
            fromCircuitMap: fromCircuitMap,
            startEditing: startEditing,
          );

/// The route of each note screen that is open right now, by note id.
///
/// Both note screens edit the shared [Note] instance and write their own
/// controllers back into it when they save or close. Two screens open on one
/// note would overwrite each other's edits, so the circuit map checks here and
/// returns to a screen that is already open instead of opening a second one.
class OpenNoteScreens {
  OpenNoteScreens._();

  static final Map<String, Route<dynamic>> _routes = {};

  static void register(String noteId, Route<dynamic> route) =>
      _routes[noteId] = route;

  /// Forgets [noteId]'s screen, but only if [route] is still the one on
  /// record (a newer screen for the same note may have registered since).
  static void unregister(String noteId, Route<dynamic> route) {
    if (identical(_routes[noteId], route)) _routes.remove(noteId);
  }

  /// The route of the open screen for [noteId], or null if none is open.
  static Route<dynamic>? routeFor(String noteId) {
    final route = _routes[noteId];
    return (route != null && route.isActive) ? route : null;
  }
}
