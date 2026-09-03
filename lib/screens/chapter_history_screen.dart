import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/note.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_route.dart';
import '../widgets/frosted_chrome.dart';

/// A chapter's version history as a vertical timeline: the live "current"
/// state on top, then each saved snapshot newest-first, with word-count deltas
/// and previews. Tapping a snapshot previews it and offers a restore.
class ChapterHistoryScreen extends StatelessWidget {
  const ChapterHistoryScreen({super.key, required this.noteId});

  final String noteId;

  static const _green = Color(0xFF3C9A5F);
  static const _red = Color(0xFFE0567B);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final note = state.noteById(noteId);
    if (note == null) {
      return FrostedScaffold(title: context.t.versionHistory, body: const SizedBox.shrink());
    }
    final family =
        note.bookId != null ? state.bookById(note.bookId!)?.fontFamily : null;

    // The live state first, then snapshots newest → oldest.
    final rows = <_Row>[
      _Row.current(note.wordCount),
      for (final s in note.history.reversed) _Row.snap(s),
    ];

    return FrostedScaffold(
      title: context.t.versionHistory,
      actions: [
        FrostedCircleButton(
          icon: Icons.bookmark_add_outlined,
          tooltip: context.t.saveVersion,
          onTap: () async {
            await state.saveChapterVersion(noteId);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.t.versionSavedToast)),
              );
            }
          },
        ),
      ],
      body: note.history.isEmpty
          ? _Empty(onSave: () async {
              await state.saveChapterVersion(noteId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.t.versionSavedToast)),
                );
              }
            })
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                // Delta vs the next-older row (positive = words added since).
                final delta = i < rows.length - 1
                    ? row.words - rows[i + 1].words
                    : null;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Rail(
                        isFirst: i == 0,
                        isLast: i == rows.length - 1,
                        color: row.isCurrent
                            ? AppPalette.scheme.primary
                            : row.snap!.auto
                                ? AppPalette.inkSecondary
                                : AppPalette.scheme.primary,
                      ),
                      Expanded(
                        child: _Card(
                          row: row,
                          delta: delta,
                          onTap: row.isCurrent
                              ? null
                              : () => Navigator.of(context).push(
                                    cupertinoRoute(
                                      _VersionPreviewScreen(
                                        noteId: noteId,
                                        snapshotId: row.snap!.id,
                                        fontFamily: family,
                                      ),
                                    ),
                                  ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// A timeline entry: the live current state, or a saved snapshot.
class _Row {
  _Row.current(this.words)
      : isCurrent = true,
        snap = null;
  _Row.snap(NoteSnapshot s)
      : isCurrent = false,
        snap = s,
        words = s.wordCount;

  final bool isCurrent;
  final NoteSnapshot? snap;
  late final int words;
}

/// The dot + connecting line on the left of a timeline row.
class _Rail extends StatelessWidget {
  const _Rail({required this.isFirst, required this.isLast, required this.color});

  final bool isFirst;
  final bool isLast;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final line = AppPalette.cardOutline;
    return SizedBox(
      width: 30,
      child: Stack(
        children: [
          if (!isFirst)
            Positioned(
                left: 14, top: 0, height: 20, width: 2,
                child: ColoredBox(color: line)),
          if (!isLast)
            Positioned(
                left: 14, top: 20, bottom: 0, width: 2,
                child: ColoredBox(color: line)),
          Positioned(
            left: 8,
            top: 13,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: AppPalette.sheet, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.row, required this.delta, this.onTap});

  final _Row row;
  final int? delta;
  final VoidCallback? onTap;

  String _label(BuildContext context) {
    if (row.isCurrent) return context.t.versionCurrent;
    return row.snap!.auto ? context.t.versionAuto : context.t.versionSaved;
  }

  Color _chipColor(BuildContext context) {
    if (row.isCurrent) return AppPalette.scheme.primary;
    return row.snap!.auto
        ? AppPalette.inkSecondary
        : AppPalette.scheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final when = row.isCurrent ? null : row.snap!.createdAt;
    final preview = row.isCurrent ? '' : row.snap!.textPreview.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppPalette.surfaceGlass,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        when == null
                            ? context.t.versionNow
                            : _relTime(context, when),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _chipColor(context).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _label(context),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: _chipColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      context.t.wordsCount(row.words),
                      style: TextStyle(
                          fontSize: 12.5, color: AppPalette.inkSecondary),
                    ),
                    if (delta != null && delta != 0) ...[
                      const SizedBox(width: 8),
                      _DeltaBadge(delta: delta!),
                    ],
                    if (onTap != null) ...[
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppPalette.inkSecondary),
                    ],
                  ],
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    preview.replaceAll('\n', ' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: AppPalette.inkSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta});
  final int delta;

  @override
  Widget build(BuildContext context) {
    final up = delta > 0;
    final color =
        up ? ChapterHistoryScreen._green : ChapterHistoryScreen._red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${up ? '+' : '−'}${delta.abs()}',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onSave});
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off_rounded,
                size: 48, color: AppPalette.inkSecondary),
            const SizedBox(height: 12),
            Text(context.t.versionHistoryEmpty,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.inkPrimary)),
            const SizedBox(height: 6),
            Text(
              context.t.versionHistoryEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppPalette.inkSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: Text(context.t.saveVersion),
            ),
          ],
        ),
      ),
    );
  }
}

/// A read-only look at one saved version, with a restore action.
class _VersionPreviewScreen extends StatelessWidget {
  const _VersionPreviewScreen({
    required this.noteId,
    required this.snapshotId,
    this.fontFamily,
  });

  final String noteId;
  final String snapshotId;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final note = state.noteById(noteId);
    NoteSnapshot? snap;
    if (note != null) {
      for (final s in note.history) {
        if (s.id == snapshotId) snap = s;
      }
    }
    if (snap == null) {
      return FrostedScaffold(
          title: context.t.versionHistory, body: const SizedBox.shrink());
    }
    final s = snap;

    return FrostedScaffold(
      title: _relTime(context, s.createdAt),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _restore(context),
        icon: const Icon(Icons.restore_rounded),
        label: Text(context.t.restoreVersion),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 100),
        children: [
          if (s.title.trim().isNotEmpty) ...[
            Text(
              s.title.trim(),
              style: TextStyle(
                fontFamily: fontFamily ?? kNoteHeadingFont,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppPalette.inkPrimary,
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            s.textPreview,
            style: TextStyle(
              fontFamily: fontFamily ?? activeBodyFont,
              fontSize: fontFamily != null ? 17 : 18,
              height: 1.55,
              color: AppPalette.inkPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.restoreVersion),
        content: Text(context.t.restoreVersionBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t.restore)),
        ],
      ),
    );
    if (ok != true) return;
    await state.restoreChapterVersion(noteId, snapshotId);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text(context.t.versionRestoredToast)),
    );
  }
}

/// "Just now" / "Today, 3:24 PM" / "Yesterday, 9:10 AM" / "Aug 8, 3:24 PM" /
/// "Aug 8, 2025".
String _relTime(BuildContext context, DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(t.year, t.month, t.day);
  final diff = today.difference(that).inDays;
  final time = DateFormat('h:mm a').format(t);
  if (now.difference(t).inMinutes < 1) return context.t.versionJustNow;
  if (diff == 0) return context.t.versionToday(time);
  if (diff == 1) return context.t.versionYesterday(time);
  if (t.year == now.year) return '${DateFormat('MMM d').format(t)}, $time';
  return DateFormat('MMM d, yyyy').format(t);
}
