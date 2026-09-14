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
Widget noteScreen(Note note, {bool isNew = false}) => note.markdown
    ? MarkdownNoteScreen(note: note, isNew: isNew)
    : NoteEditorScreen(note: note, isNew: isNew);
