import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/impulse.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/bouncy_route.dart';
import '../widgets/bubble_button.dart';
import '../widgets/frosted_chrome.dart';
import '../widgets/glass.dart';
import '../widgets/glass_morph.dart';
import 'daily_day_screen.dart';
import 'impulse_history_screen.dart';
import 'pomodoro_screen.dart';

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

enum _ReflexFilter { active, paused, done, archived }

/// The Reflexes section: the [date] stays pinned at the top (carried over from
/// the date card), the daily day plus your projects list below, and a frosted
/// filter island floating at the bottom.
class ReflexesScreen extends StatefulWidget {
  const ReflexesScreen({super.key, required this.date});

  final DateTime date;

  @override
  State<ReflexesScreen> createState() => _ReflexesScreenState();
}

class _ReflexesScreenState extends State<ReflexesScreen> {
  // The state filter lives in the vertical side tabs; the category filter in
  // the horizontal tabs below the date. Empty category = "All".
  _ReflexFilter _filter = _ReflexFilter.active;
  String _category = '';

  List<Impulse> _filtered(AppState state) {
    Iterable<Impulse> base;
    switch (_filter) {
      case _ReflexFilter.active:
        base = state.reflexes.where((i) => !i.paused && !i.isComplete);
      case _ReflexFilter.paused:
        base = state.reflexes.where((i) => i.paused);
      case _ReflexFilter.done:
        base = state.reflexes.where((i) => i.isComplete);
      case _ReflexFilter.archived:
        base = state.archivedReflexes;
    }
    if (_category.isNotEmpty) {
      base = base.where((i) => i.category.trim() == _category);
    }
    return base.toList();
  }

  String _label(_ReflexFilter f) => switch (f) {
        _ReflexFilter.active => context.t.filterActive,
        _ReflexFilter.paused => context.t.statusPaused,
        _ReflexFilter.done => context.t.filterDone,
        _ReflexFilter.archived => context.t.filterArchived,
      };

  /// A distinct accent per state, so the side tabs read at a glance (ref 1).
  Color _filterColor(_ReflexFilter f) => switch (f) {
        _ReflexFilter.active => AppPalette.journalAccent,
        _ReflexFilter.paused => const Color(0xFFF5A623),
        _ReflexFilter.done => const Color(0xFF3E8E7E),
        _ReflexFilter.archived => AppPalette.inkSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final today = state.todayKey;
    final pinnedId = state.pinnedReflexId;
    final pinned = state.pinnedReflex;
    final headerProgress =
        pinned.threads.isEmpty ? null : pinned.progress(today);
    final categories = state.reflexCategories;
    // A category tab whose last reflex was deleted/recategorised falls to "All".
    if (_category.isNotEmpty && !categories.contains(_category)) {
      _category = '';
    }
    final impulses = _filtered(state);

    return FrostedScaffold(
      floatingActionButton: BubbleButton(
        icon: Icons.edit_rounded,
        tooltip: context.t.newImpulse,
        onTap: () => showImpulseEditor(context),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The date card's content, kept at the top so opening the card reads
          // as its contents floating up — the Pomodoro and impulses below.
          _ReflexHeader(
            date: widget.date,
            projectCount: state.reflexes.length,
            progress: headerProgress,
          ),
          _pomodoroEntry(context),
          // Category tabs sit just below (only once you've used any).
          if (categories.isNotEmpty) _categoryTabs(context, categories),
          // The state filter is a strip of vertical side tabs on the left; the
          // list fills the rest. The tabs begin here (below the date), leaving
          // the top blank as asked.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sideTabs(context),
                Expanded(
                  child: impulses.isEmpty
                      ? Center(
                          child: Text(context.t.reflexesEmpty,
                              style:
                                  TextStyle(color: AppPalette.inkSecondary)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 2, 14, 96),
                          itemCount: impulses.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ImpulseCard(
                              impulse: impulses[i],
                              today: today,
                              isPinned: impulses[i].id == pinnedId,
                              onPin: () =>
                                  state.setPinnedReflex(impulses[i].id),
                              onLongPress: () => _showImpulseMenu(
                                context,
                                state,
                                impulses[i],
                                isPinned: impulses[i].id == pinnedId,
                              ),
                              // An iOS-style horizontal slide (parallax +
                              // edge-swipe back), no fade — a calmer open/close.
                              onTap: () => Navigator.of(context).push(
                                CupertinoPageRoute(
                                  builder: (_) => ImpulseDetailScreen(
                                      impulseId: impulses[i].id),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Vertical side tabs (ref 1): one per state, equal height, filling from just
  /// below the date to the bottom. The first (Active) is selected on open.
  Widget _sideTabs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 2, bottom: 96),
      child: SizedBox(
        width: 40,
        child: Column(
          children: [
            for (final f in _ReflexFilter.values)
              Expanded(child: _sideTab(context, f)),
          ],
        ),
      ),
    );
  }

  Widget _sideTab(BuildContext context, _ReflexFilter f) {
    final selected = _filter == f;
    final color = _filterColor(f);
    return GestureDetector(
      onTap: () => setState(() => _filter = f),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.14),
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(16),
            right: Radius.circular(6),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
            _label(f),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }

  /// Horizontal category tabs below the date: "All" plus each category in use.
  Widget _categoryTabs(BuildContext context, List<String> categories) {
    final tabs = ['', ...categories];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _categoryChip(context, tabs[i]),
      ),
    );
  }

  Widget _categoryChip(BuildContext context, String c) {
    final selected = _category == c;
    final label = c.isEmpty ? context.t.filterAll : c;
    return GestureDetector(
      onTap: () => setState(() => _category = c),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              selected ? AppPalette.scheme.primary : AppPalette.bubbleGlass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppPalette.scheme.primary
                : AppPalette.cardOutline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected
                ? AppPalette.scheme.onPrimary
                : AppPalette.inkSecondary,
          ),
        ),
      ),
    );
  }

  /// The Pomodoro entry — opens the focus timer with the same container
  /// transform the date card uses to open this screen.
  Widget _pomodoroEntry(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GlassMorph(
        closedRadius: 18,
        openBuilder: (_) => const PomodoroScreen(),
        closedBuilder: (context, open) => _PomodoroCard(onTap: open),
      ),
    );
  }
}

/// A slim entry card for the Pomodoro timer, styled like the date card.
class _PomodoroCard extends StatelessWidget {
  const _PomodoroCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.bubbleGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.scheme.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.timer_outlined,
                  size: 21, color: AppPalette.scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t.pomodoro,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary)),
                  const SizedBox(height: 1),
                  Text(context.t.focusTimer,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.inkSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 22, color: AppPalette.inkSecondary),
          ],
        ),
      ),
    );
  }
}

/// The date card's content, kept at the top of the reflex screen so opening the
/// card reads as its contents floating up.
class _ReflexHeader extends StatelessWidget {
  const _ReflexHeader({
    required this.date,
    required this.projectCount,
    required this.progress,
  });

  final DateTime date;
  final int projectCount;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${date.day}',
                  style: TextStyle(
                      fontSize: 44,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary)),
          const SizedBox(width: 6),
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppPalette.journalAccent,
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(DateFormat("MMM''yy").format(date),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.inkSecondary)),
              Text(DateFormat('EEEE').format(date),
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary)),
            ],
          ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.bolt_rounded,
                  size: 18, color: Color(0xFFF5A623)),
              const SizedBox(width: 8),
              Text(context.t.reflexes,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary)),
              const Spacer(),
              if (progress != null) ...[
                Text('${(progress! * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.journalAccent)),
                const SizedBox(width: 8),
              ],
              Text(context.t.reflexesProjects(projectCount),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.inkSecondary)),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppPalette.cardOutline,
                valueColor: const AlwaysStoppedAnimation<Color>(
                    AppPalette.journalAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const _completeGreen = Color(0xFF2FA36B);

/// Long-press options for a reflex: pin/unpin, pause/resume, mark complete (or
/// reopen), colour-code and archive it. The daily day is an ordinary reflex now,
/// so it gets the same full menu.
Future<void> _showImpulseMenu(
  BuildContext context,
  AppState state,
  Impulse impulse, {
  required bool isPinned,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                    isPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    color: AppPalette.inkPrimary),
                title: Text(isPinned
                    ? context.t.unpinFromFeed
                    : context.t.pinToFeed),
                onTap: () => Navigator.pop(context, 'pin'),
              ),
              ListTile(
                leading: Icon(
                    impulse.paused
                        ? Icons.play_circle_outline_rounded
                        : Icons.pause_circle_outline_rounded,
                    color: AppPalette.inkPrimary),
                title: Text(impulse.paused
                    ? context.t.resumeImpulse
                    : context.t.pauseImpulse),
                onTap: () => Navigator.pop(context, 'pause'),
              ),
              ListTile(
                leading: Icon(
                    impulse.isCompletedManually
                        ? Icons.refresh_rounded
                        : Icons.check_circle_outline_rounded,
                    color: impulse.isCompletedManually
                        ? AppPalette.inkPrimary
                        : _completeGreen),
                title: Text(impulse.isCompletedManually
                    ? context.t.markActive
                    : context.t.markComplete),
                onTap: () => Navigator.pop(context, 'complete'),
              ),
              ListTile(
                leading: Icon(Icons.palette_outlined,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.noteColor),
                onTap: () => Navigator.pop(context, 'colour'),
              ),
              ListTile(
                leading: Icon(
                    impulse.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    color: AppPalette.inkPrimary),
                title: Text(impulse.archived
                    ? context.t.unarchiveImpulse
                    : context.t.archiveImpulse),
                onTap: () => Navigator.pop(context, 'archive'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (choice == null) return;
  switch (choice) {
    case 'pin':
      await state.setPinnedReflex(isPinned ? AppState.dailyDayId : impulse.id);
    case 'pause':
      await state.setImpulsePaused(impulse.id, !impulse.paused);
    case 'complete':
      await state.setImpulseCompleted(
          impulse.id, !impulse.isCompletedManually);
    case 'colour':
      if (context.mounted) await _pickImpulseColor(context, state, impulse);
    case 'archive':
      await state.setImpulseArchived(impulse.id, !impulse.archived);
  }
}

/// A swatch grid to colour-code an impulse (mirrors the note colour picker).
Future<void> _pickImpulseColor(
    BuildContext context, AppState state, Impulse impulse) async {
  final selected = await showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(context.t.noteColor,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppPalette.inkPrimary)),
              ),
              GridView.count(
                crossAxisCount: 5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _colorDot(context, null, impulse.colorValue == null,
                      () => Navigator.pop(context, NoteColors.none)),
                  for (final c in NoteColors.swatches)
                    _colorDot(context, c, impulse.colorValue == c,
                        () => Navigator.pop(context, c)),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (selected == null) return;
  await state.setImpulseColor(
      impulse.id, selected == NoteColors.none ? null : selected);
}

Widget _colorDot(
    BuildContext context, int? swatch, bool selected, VoidCallback onTap) {
  final color = swatch == null ? null : Color(swatch);
  return GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? Colors.transparent,
        border: Border.all(
          color: selected ? AppPalette.inkPrimary : Colors.black26,
          width: selected ? 3 : 1.5,
        ),
      ),
      child: color == null
          ? Icon(Icons.format_color_reset_rounded,
              size: 20, color: AppPalette.inkSecondary)
          : (selected
              ? Icon(Icons.check_rounded,
                  size: 20, color: Colors.black.withValues(alpha: 0.6))
              : null),
    ),
  );
}

/// A reflex card: title, a pin toggle (features it in the journal feed), a
/// small description, the progress bar and a meta line.
class _ImpulseCard extends StatelessWidget {
  const _ImpulseCard({
    required this.impulse,
    required this.today,
    required this.isPinned,
    required this.onPin,
    required this.onTap,
    this.onLongPress,
  });

  final Impulse impulse;
  final String today;
  final bool isPinned;
  final VoidCallback onPin;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  Widget _statusPill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final complete = impulse.isComplete;
    // Long-term goals count every nested thread; others just their flat list.
    final all = impulse.isLongTerm ? impulse.allThreads : impulse.threads;
    final total = all.length;
    final done =
        all.where((t) => impulse.threadDone(t, today)).length;
    // A completed impulse reads as full and green, whatever the thread count.
    final progress =
        complete ? 1.0 : (total == 0 ? 0.0 : done / total);
    final pct = complete ? 100 : (progress * 100).round();
    final barColor =
        complete ? const Color(0xFF2FA36B) : AppPalette.scheme.primary;
    final title = impulse.title.trim().isEmpty
        ? context.t.untitledImpulse
        : impulse.title;
    final description = impulse.goal.trim();

    final card = GlassPanel(
      borderRadius: 20,
      blur: 0,
      // Colour-coded fill when the impulse has a colour, else the plain glass.
      color: NoteColors.resolve(impulse.colorValue) ?? AppPalette.surfaceGlass,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkPrimary,
                  ),
                ),
              ),
              if (impulse.paused)
                _statusPill(context.t.statusPaused, const Color(0xFFEA8A2E))
              else if (complete)
                _statusPill(
                    context.t.statusCompleted, const Color(0xFF2FA36B)),
              if (impulse.paused || complete) const SizedBox(width: 8),
              GestureDetector(
                onTap: onPin,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Icon(
                    isPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    size: 19,
                    color: isPinned
                        ? AppPalette.scheme.primary
                        : AppPalette.inkSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text('$pct%',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: barColor,
                  )),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppPalette.inkSecondary),
            ),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppPalette.cardOutline,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MetaChip(
                icon: impulse.isDaily
                    ? Icons.event_repeat_rounded
                    : Icons.checklist_rounded,
                label: impulse.isDaily
                    ? context.t.todayLabel
                    : context.t.overallLabel,
              ),
              const SizedBox(width: 8),
              _MetaChip(
                icon: Icons.task_alt_rounded,
                label: '$done/$total',
              ),
              const Spacer(),
              if (impulse.deadline != null)
                Text(
                  _deadlineText(context, impulse.deadline!),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _deadlineOverdue(impulse.deadline!)
                        ? const Color(0xFFE0567B)
                        : AppPalette.inkSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    // Paused impulses stay in the list but read as on-hold.
    return impulse.paused ? Opacity(opacity: 0.6, child: card) : card;
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppPalette.inkSecondary),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: AppPalette.inkSecondary)),
      ],
    );
  }
}

/// An opened Impulse: its details on top, then its Threads to tick off.
class ImpulseDetailScreen extends StatefulWidget {
  const ImpulseDetailScreen({super.key, required this.impulseId});
  final String impulseId;

  @override
  State<ImpulseDetailScreen> createState() => _ImpulseDetailScreenState();
}

class _ImpulseDetailScreenState extends State<ImpulseDetailScreen> {
  // Open impulses default to a read-only "tick things off" view; the pencil
  // toggles into edit mode where you can add/rename/reorder structure.
  bool _editMode = false;

  Future<void> _menu(BuildContext context, Impulse impulse) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassPanel(
            borderRadius: 26,
            strong: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.low_priority_rounded,
                      color: AppPalette.inkPrimary),
                  title: Text(context.t.sortByPriority),
                  onTap: () => Navigator.pop(context, 'sort'),
                ),
                // Retime every task at once (a shared time window).
                if (impulse.allThreads.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.schedule_rounded,
                        color: AppPalette.inkPrimary),
                    title: Text(context.t.changeAllTimes),
                    onTap: () => Navigator.pop(context, 'time'),
                  ),
                ListTile(
                  leading: Icon(Icons.edit_outlined,
                      color: AppPalette.inkPrimary),
                  title: Text(context.t.editImpulse),
                  onTap: () => Navigator.pop(context, 'edit'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFE0567B)),
                  title: Text(context.t.deleteImpulse),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    final state = context.read<AppState>();
    if (choice == 'sort') {
      await state.sortThreadsByFlag(widget.impulseId);
    } else if (choice == 'time') {
      await _changeAllTimes(context, impulse);
    } else if (choice == 'edit') {
      await showImpulseEditor(context, existing: impulse);
    } else if (choice == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t.deleteImpulse),
          content: Text(context.t.deleteImpulseConfirm),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.t.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.t.delete)),
          ],
        ),
      );
      if (ok == true) {
        await state.deleteImpulse(widget.impulseId);
        if (context.mounted) Navigator.of(context).pop();
      }
    }
  }

  /// Retimes every task in the impulse to one shared window (a shortcut when
  /// they all sit in the same slot, e.g. a fixed study hour).
  Future<void> _changeAllTimes(BuildContext context, Impulse impulse) async {
    // Seed from the first task that already has a time, so it feels like
    // nudging the current window rather than starting cold.
    int? seedStart;
    int? seedEnd;
    for (final t in impulse.allThreads) {
      if (t.reminderMinutes != null) {
        seedStart = t.reminderMinutes;
        seedEnd = t.endMinutes;
        break;
      }
    }
    final result = await showModalBottomSheet<({int start, int? end})>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _BulkTimeSheet(initialStart: seedStart, initialEnd: seedEnd),
    );
    if (result == null || !context.mounted) return;
    final state = context.read<AppState>();
    final count = await state.setImpulseThreadsTime(
        widget.impulseId, result.start, result.end);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.t.allTimesUpdated(count)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final impulse = state.impulseById(widget.impulseId);
    if (impulse == null) {
      return FrostedScaffold(
          title: context.t.tabReflexes, body: const SizedBox.shrink());
    }
    final today = state.todayKey;
    final isLong = impulse.isLongTerm;
    // Long-term goals sum today's completion across every nested thread.
    final all = impulse.allThreads;
    final progress = isLong
        ? (all.isEmpty
            ? 0.0
            : all.where((t) => impulse.threadDone(t, today)).length /
                all.length)
        : impulse.progress(today);
    final pct = (progress * 100).round();
    final barColor = impulse.isComplete
        ? const Color(0xFF2FA36B)
        : AppPalette.scheme.primary;

    return FrostedScaffold(
      title:
          impulse.title.trim().isEmpty ? context.t.untitledImpulse : impulse.title,
      actions: [
        FrostedCircleButton(
          icon: Icons.more_horiz_rounded,
          tooltip: context.t.moreOptions,
          onTap: () => _menu(context, impulse),
        ),
      ],
      body: ListView(
        // Extra bottom room so the last threads clear the floating edit button.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          // Overview: goal, progress, meta.
          GlassPanel(
            borderRadius: 20,
            blur: 0,
            color: AppPalette.surfaceGlass,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (impulse.goal.trim().isNotEmpty) ...[
                  Text(context.t.impulseGoal.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkSecondary)),
                  const SizedBox(height: 4),
                  Text(impulse.goal.trim(),
                      style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: AppPalette.inkPrimary)),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Text(
                      impulse.isDaily
                          ? context.t.todayLabel
                          : context.t.overallLabel,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkSecondary),
                    ),
                    const Spacer(),
                    Text('$pct%',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: barColor)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: AppPalette.cardOutline,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    _MetaChip(
                      icon: isLong
                          ? Icons.account_tree_rounded
                          : impulse.isDaily
                              ? Icons.event_repeat_rounded
                              : Icons.checklist_rounded,
                      label: isLong
                          ? context.t.modeLongTerm
                          : impulse.isDaily
                              ? context.t.modeDaily
                              : context.t.modeChecklist,
                    ),
                    if (impulse.startDate != null)
                      _MetaChip(
                        icon: Icons.play_circle_outline_rounded,
                        label: DateFormat('MMM d, yyyy')
                            .format(impulse.startDate!),
                      ),
                    if (impulse.deadline != null)
                      _MetaChip(
                        icon: Icons.flag_outlined,
                        label: DateFormat('MMM d, yyyy')
                            .format(impulse.deadline!),
                      ),
                  ],
                ),
                if (impulse.days.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _DayChips(selected: impulse.days),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (isLong) ...[
            // Long-term goals get the same consistency heatmap (spanning the
            // whole goal), then the curriculum tree.
            _ReflexHeatmap(
                impulse: impulse, streak: state.streakFor(impulse)),
            const SizedBox(height: 22),
            _LongTermBody(impulse: impulse, editMode: _editMode),
          ] else ...[
            // The completion heatmap over the goal's lifespan.
            _ReflexHeatmap(
                impulse: impulse, streak: state.streakFor(impulse)),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(context.t.threadsSection.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkSecondary)),
            ),
            if (impulse.threads.isEmpty && !_editMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                child: Text(context.t.noThreads,
                    style: TextStyle(
                        color: AppPalette.inkSecondary, height: 1.4)),
              )
            else if (impulse.threads.isNotEmpty)
              // View mode: tick tasks. Edit mode: reorder + open the sheet.
              TaskRowsList(
                impulseId: impulse.id,
                threads: impulse.threads,
                date: DateTime.now(),
                allowOpen: _editMode,
                onReorder: _editMode
                    ? (oldIndex, newIndex) =>
                        state.reorderThread(impulse.id, oldIndex, newIndex)
                    : null,
              ),
            if (_editMode) ...[
              const SizedBox(height: 10),
              _AddRow(
                label: context.t.newThread,
                onTap: () =>
                    openNewThread(context, impulse.id, DateTime.now()),
              ),
            ],
          ],
        ],
      ),
      // The pencil flips between the read-only view and edit mode.
      floatingActionButton: BubbleButton(
        icon: _editMode ? Icons.check_rounded : Icons.edit_rounded,
        tooltip: _editMode ? context.t.done : context.t.edit,
        onTap: () => setState(() => _editMode = !_editMode),
      ),
    );
  }
}

/// The "change all times" sheet: pick a start time and an optional end, then
/// Apply to stamp that one window onto every task in the impulse.
class _BulkTimeSheet extends StatefulWidget {
  const _BulkTimeSheet({this.initialStart, this.initialEnd});
  final int? initialStart;
  final int? initialEnd;

  @override
  State<_BulkTimeSheet> createState() => _BulkTimeSheetState();
}

class _BulkTimeSheetState extends State<_BulkTimeSheet> {
  int? _start;
  int? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  String _fmt(BuildContext context, int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

  Future<void> _pickStart() async {
    final init = _start != null
        ? TimeOfDay(hour: _start! ~/ 60, minute: _start! % 60)
        : TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked == null) return;
    setState(() => _start = picked.hour * 60 + picked.minute);
  }

  Future<void> _pickEnd() async {
    final base = _end ?? (_start != null ? (_start! + 60) % (24 * 60) : null);
    final init = base != null
        ? TimeOfDay(hour: base ~/ 60, minute: base % 60)
        : TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked == null) return;
    setState(() => _end = picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t.changeAllTimes,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary)),
              const SizedBox(height: 4),
              Text(context.t.changeAllTimesHint,
                  style:
                      TextStyle(fontSize: 13, color: AppPalette.inkSecondary)),
              const SizedBox(height: 16),
              _row(
                context.t.startTime,
                _start != null ? _fmt(context, _start!) : context.t.setTime,
                _pickStart,
              ),
              const SizedBox(height: 10),
              _row(
                context.t.endTime,
                _end != null ? _fmt(context, _end!) : context.t.noEndTime,
                _pickEnd,
                onClear:
                    _end != null ? () => setState(() => _end = null) : null,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.t.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _start == null
                          ? null
                          : () => Navigator.pop(
                              context, (start: _start!, end: _end)),
                      child: Text(context.t.apply),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, VoidCallback onTap,
      {VoidCallback? onClear}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppPalette.bubbleGlass,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.cardOutline),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded,
                size: 18, color: AppPalette.inkSecondary),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkPrimary)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.inkSecondary)),
            if (onClear != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close_rounded,
                    size: 18, color: AppPalette.inkSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A GitHub-style completion heatmap that spans the impulse's whole life — from
/// its start (or creation) to its deadline — one square per day, shaded by how
/// much of the reflex was done that day. Days before today are history; days up
/// to the deadline show as faint "upcoming" cells so the remaining runway is
/// visible. Mon–Sun rows stay aligned; it opens scrolled to today and scrolls
/// back to the start or forward to the deadline. A footer counts completed days.
class _ReflexHeatmap extends StatefulWidget {
  const _ReflexHeatmap({required this.impulse, required this.streak});
  final Impulse impulse;
  final ReflexStreak streak;

  @override
  State<_ReflexHeatmap> createState() => _ReflexHeatmapState();
}

class _ReflexHeatmapState extends State<_ReflexHeatmap> {
  static const _cell = 12.0;
  static const _gap = 3.0;
  static const _colW = _cell + _gap;

  final _scrollCtrl = ScrollController();
  bool _didAutoScroll = false;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final impulse = widget.impulse;
    final streak = widget.streak;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // The window runs from the start (explicit start date, else creation) to
    // the deadline. With no deadline it grows to today.
    final startDay = impulse.consistencyStart;
    var endDay = impulse.deadline == null
        ? today
        : DateTime(impulse.deadline!.year, impulse.deadline!.month,
            impulse.deadline!.day);
    if (endDay.isBefore(startDay)) endDay = startDay;

    // Anchor the grid to the Monday on/before the first day so weekday rows line
    // up; the leading out-of-range cells become invisible spacers.
    final gridOrigin = startDay.subtract(Duration(days: startDay.weekday - 1));
    final cols = (endDay.difference(gridOrigin).inDays / 7).floor() + 1;

    // The thread set the heatmap scores — long-term goals pull in their nested
    // curriculum threads, not just the flat reminder list.
    final threads = impulse.isLongTerm ? impulse.allThreads : impulse.threads;

    // Footer counters: window length and how many elapsed days had every task
    // that was due that day ticked (a "complete" day).
    final totalDays = endDay.difference(startDay).inDays + 1;
    var doneDays = 0;
    for (var c = startDay;
        !c.isAfter(endDay) && !c.isAfter(today);
        c = c.add(const Duration(days: 1))) {
      final (done, scheduled) = _dayTally(threads, c);
      if (scheduled > 0 && done >= scheduled) doneDays++;
    }
    final daysLeft = endDay.difference(today).inDays;

    // Open scrolled so today sits near the right edge (recent activity in view),
    // with the start and the deadline a scroll away.
    if (!_didAutoScroll) {
      _didAutoScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        final anchor = today.isAfter(endDay) ? endDay : today;
        final col = (anchor.difference(gridOrigin).inDays / 7).floor();
        final target =
            (col + 1) * _colW - _scrollCtrl.position.viewportDimension;
        _scrollCtrl
            .jumpTo(target.clamp(0.0, _scrollCtrl.position.maxScrollExtent));
      });
    }

    return GestureDetector(
      // Tapping the heatmap opens the full day-by-day history calendar, with
      // the iOS-style left/right slide push.
      onTap: () => Navigator.of(context).push(
        cupertinoRoute(ImpulseHistoryScreen(impulseId: impulse.id)),
      ),
      behavior: HitTestBehavior.opaque,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(context.t.consistencyHeatmap.toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkSecondary)),
            const SizedBox(width: 5),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: AppPalette.inkSecondary),
            const Spacer(),
            if (streak.current > 0) ...[
              const Icon(Icons.local_fire_department_rounded,
                  size: 15, color: Color(0xFFF5A623)),
              const SizedBox(width: 3),
              Text(context.t.streakDays(streak.current),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.inkPrimary)),
            ],
            if (streak.best > 1) ...[
              const SizedBox(width: 8),
              Text(context.t.streakBest(streak.best),
                  style: TextStyle(
                      fontSize: 12, color: AppPalette.inkSecondary)),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 7 * _cell + 6 * _gap,
          child: ListView.builder(
            controller: _scrollCtrl,
            scrollDirection: Axis.horizontal,
            itemCount: cols,
            padding: EdgeInsets.zero,
            itemBuilder: (ctx, w) => Padding(
              padding: const EdgeInsets.only(right: _gap),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var d = 0; d < 7; d++)
                    Padding(
                      padding: EdgeInsets.only(bottom: d == 6 ? 0 : _gap),
                      child: _cellFor(gridOrigin.add(Duration(days: w * 7 + d)),
                          startDay, endDay, today, threads),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          daysLeft > 0
              ? '${context.t.heatmapDaysDone(doneDays, totalDays)}  ·  ${context.t.heatmapDaysLeft(daysLeft)}'
              : context.t.heatmapDaysDone(doneDays, totalDays),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppPalette.inkSecondary),
        ),
      ],
      ),
    );
  }

  /// (done, scheduled) for [day]: how many of the day's due threads are ticked,
  /// and how many were due. A one-time [Thread.once] task, and every milestone
  /// of a checklist reflex, counts only on the day it was completed; every
  /// other thread counts on the weekdays it runs (empty = every day). Kept
  /// identical to the history calendar so both read the same.
  (int done, int scheduled) _dayTally(List<Thread> threads, DateTime day) {
    final key = AppState.dayKeyFor(day);
    final onceLike = widget.impulse.mode == ImpulseMode.checklist;
    var done = 0;
    var scheduled = 0;
    for (final t in threads) {
      if (t.once || onceLike) {
        if (t.doneDays.contains(key)) {
          scheduled++;
          done++;
        }
      } else if (t.days.isEmpty || t.days.contains(day.weekday)) {
        scheduled++;
        if (t.doneDays.contains(key)) done++;
      }
    }
    return (done, scheduled);
  }

  Widget _cellFor(DateTime day, DateTime startDay, DateTime endDay,
      DateTime today, List<Thread> threads) {
    // Outside the created→deadline window: an invisible spacer that keeps the
    // weekday rows aligned.
    if (day.isBefore(startDay) || day.isAfter(endDay)) {
      return const SizedBox(width: _cell, height: _cell);
    }
    Color color;
    if (day.isAfter(today)) {
      // Upcoming day before the deadline — a faint placeholder.
      color = AppPalette.cardOutline.withValues(alpha: 0.16);
    } else {
      final (done, scheduled) = _dayTally(threads, day);
      if (scheduled == 0) {
        // Nothing was due this day.
        color = AppPalette.cardOutline.withValues(alpha: 0.25);
      } else {
        // Intensity tracks the *percentage* of the day's tasks completed, so it
        // reads correctly no matter how many tasks there are.
        final frac = done / scheduled;
        if (frac >= 1.0) {
          color = AppPalette.journalAccent;
        } else if (frac > 0) {
          color = Color.lerp(AppPalette.cardOutline, AppPalette.journalAccent,
              0.3 + frac * 0.5)!;
        } else {
          color = AppPalette.cardOutline.withValues(alpha: 0.5);
        }
      }
    }
    return Container(
      width: _cell,
      height: _cell,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// A read-only Mon–Sun strip with the consistency days highlighted.
class _DayChips extends StatelessWidget {
  const _DayChips({required this.selected});
  final Set<int> selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var d = 1; d <= 7; d++) ...[
          if (d > 1) const SizedBox(width: 6),
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected.contains(d)
                  ? AppPalette.scheme.primary
                  : Colors.transparent,
              border: Border.all(
                color: selected.contains(d)
                    ? AppPalette.scheme.primary
                    : AppPalette.cardOutline,
              ),
            ),
            child: Text(
              _weekdayLetters[d - 1],
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: selected.contains(d)
                    ? AppPalette.scheme.onPrimary
                    : AppPalette.inkSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---- Deadline helpers ------------------------------------------------------

bool _deadlineOverdue(DateTime deadline) {
  final now = DateTime.now();
  final d = DateTime(deadline.year, deadline.month, deadline.day);
  final today = DateTime(now.year, now.month, now.day);
  return d.isBefore(today);
}

String _deadlineText(BuildContext context, DateTime deadline) {
  final now = DateTime.now();
  final d = DateTime(deadline.year, deadline.month, deadline.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = d.difference(today).inDays;
  if (days < 0) return context.t.overdue;
  return context.t.daysLeft(days);
}

// ---- Create / edit ---------------------------------------------------------

Future<void> showImpulseEditor(BuildContext context, {Impulse? existing}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _ImpulseEditorScreen(existing: existing),
    ),
  );
}

class _ImpulseEditorScreen extends StatefulWidget {
  const _ImpulseEditorScreen({this.existing});
  final Impulse? existing;

  @override
  State<_ImpulseEditorScreen> createState() => _ImpulseEditorScreenState();
}

class _ImpulseEditorScreenState extends State<_ImpulseEditorScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _goal =
      TextEditingController(text: widget.existing?.goal ?? '');
  late final TextEditingController _category =
      TextEditingController(text: widget.existing?.category ?? '');
  late DateTime? _startDate = widget.existing?.startDate;
  late DateTime? _deadline = widget.existing?.deadline;
  late String _mode = widget.existing?.mode ?? ImpulseMode.daily;
  late final Set<int> _days = {...?widget.existing?.days};

  @override
  void dispose() {
    _title.dispose();
    _goal.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    // A start may sit in the past; cap it at the deadline if one is set.
    final first = DateTime(now.year - 5);
    final last = _deadline ?? now.add(const Duration(days: 365 * 10));
    var init = _startDate ?? now;
    if (init.isBefore(first)) init = first;
    if (init.isAfter(last)) init = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final floor = _startDate ?? now;
    final last = floor.add(const Duration(days: 365 * 10));
    var init = _deadline ?? floor.add(const Duration(days: 30));
    if (init.isBefore(floor)) init = floor;
    if (init.isAfter(last)) init = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: floor,
      lastDate: last,
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final state = context.read<AppState>();
    final existing = widget.existing;
    if (existing == null) {
      await state.addImpulse(
        title: title,
        goal: _goal.text.trim(),
        startDate: _startDate,
        deadline: _deadline,
        mode: _mode,
        category: _category.text.trim(),
        days: _days,
      );
    } else {
      existing
        ..title = title
        ..goal = _goal.text.trim()
        ..startDate = _startDate
        ..deadline = _deadline
        ..mode = _mode
        ..category = _category.text.trim()
        ..days = {..._days};
      await state.updateImpulse(existing);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return FrostedScaffold(
      title: widget.existing == null
          ? context.t.newImpulse
          : context.t.editImpulse,
      actions: [
        FrostedCircleButton(
          icon: Icons.check_rounded,
          tooltip: context.t.save,
          onTap: _save,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 60),
        children: [
          _label(context, context.t.impulseTitle),
          _field(_title, context.t.impulseTitleHint, autofocus: true),
          const SizedBox(height: 18),
          _label(context, context.t.impulseGoal),
          _field(_goal, context.t.impulseGoalHint, maxLines: 2),
          const SizedBox(height: 18),
          _label(context, context.t.impulseCategory),
          _field(_category, context.t.impulseCategoryHint),
          _CategorySuggestions(
            onPick: (c) => setState(() {
              _category.text = c;
              _category.selection =
                  TextSelection.collapsed(offset: c.length);
            }),
          ),
          const SizedBox(height: 18),
          _label(context, context.t.impulseMode),
          _modeOption(ImpulseMode.daily, context.t.modeDaily,
              context.t.modeDailyDesc, Icons.event_repeat_rounded),
          const SizedBox(height: 8),
          _modeOption(ImpulseMode.checklist, context.t.modeChecklist,
              context.t.modeChecklistDesc, Icons.checklist_rounded),
          const SizedBox(height: 8),
          _modeOption(ImpulseMode.longTerm, context.t.modeLongTerm,
              context.t.modeLongTermDesc, Icons.account_tree_rounded),
          const SizedBox(height: 18),
          _label(context, context.t.impulseStartDate),
          _DateRow(
            date: _startDate,
            placeholder: context.t.noStartDate,
            icon: Icons.play_circle_outline_rounded,
            onPick: _pickStartDate,
            onClear: () => setState(() => _startDate = null),
          ),
          const SizedBox(height: 18),
          _label(context, context.t.impulseDeadline),
          _DateRow(
            date: _deadline,
            placeholder: context.t.noDeadline,
            icon: Icons.event_outlined,
            onPick: _pickDeadline,
            onClear: () => setState(() => _deadline = null),
          ),
          const SizedBox(height: 18),
          _label(context, context.t.consistency),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.t.consistencyHint,
                style: TextStyle(
                    fontSize: 12.5, color: AppPalette.inkSecondary)),
          ),
          _EditableDayChips(
            selected: _days,
            onToggle: (d) => setState(() {
              _days.contains(d) ? _days.remove(d) : _days.add(d);
            }),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: AppPalette.inkSecondary)),
      );

  Widget _field(TextEditingController c, String hint,
      {int maxLines = 1, bool autofocus = false}) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(color: AppPalette.inkPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppPalette.inkSecondary),
        filled: true,
        fillColor: AppPalette.bubbleGlass,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _modeOption(
      String mode, String label, String desc, IconData icon) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppPalette.scheme.primary.withValues(alpha: 0.10)
              : AppPalette.bubbleGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppPalette.scheme.primary
                : AppPalette.cardOutline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 22,
                color: selected
                    ? AppPalette.scheme.primary
                    : AppPalette.inkSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkPrimary)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: AppPalette.inkSecondary)),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? AppPalette.scheme.primary
                  : AppPalette.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow(
      {required this.date,
      required this.placeholder,
      required this.icon,
      required this.onPick,
      required this.onClear});
  final DateTime? date;
  final String placeholder;
  final IconData icon;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.bubbleGlass,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPick,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppPalette.inkSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  date == null
                      ? placeholder
                      : DateFormat('EEEE, MMMM d, yyyy').format(date!),
                  style: TextStyle(
                      color: date == null
                          ? AppPalette.inkSecondary
                          : AppPalette.inkPrimary),
                ),
              ),
              if (date != null)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded,
                        size: 18, color: AppPalette.inkSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableDayChips extends StatelessWidget {
  const _EditableDayChips({required this.selected, required this.onToggle});
  final Set<int> selected;
  final void Function(int day) onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var d = 1; d <= 7; d++)
          GestureDetector(
            onTap: () => onToggle(d),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected.contains(d)
                    ? AppPalette.scheme.primary
                    : Colors.transparent,
                border: Border.all(
                  color: selected.contains(d)
                      ? AppPalette.scheme.primary
                      : AppPalette.cardOutline,
                  width: 1.4,
                ),
              ),
              child: Text(
                _weekdayLetters[d - 1],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected.contains(d)
                      ? AppPalette.scheme.onPrimary
                      : AppPalette.inkSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Tap-to-fill chips for the category field: the categories already in use,
/// plus a couple of common defaults so the first reflex has something to pick.
class _CategorySuggestions extends StatelessWidget {
  const _CategorySuggestions({required this.onPick});
  final void Function(String category) onPick;

  @override
  Widget build(BuildContext context) {
    final used = context.watch<AppState>().reflexCategories;
    final defaults = [context.t.categoryWork, context.t.categoryPersonal];
    final options = <String>[
      ...used,
      for (final d in defaults)
        if (!used.any((u) => u.toLowerCase() == d.toLowerCase())) d,
    ];
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in options)
            GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppPalette.bubbleGlass,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.cardOutline),
                ),
                child: Text(
                  c,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.inkPrimary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- Long-term goal tree ---------------------------------------------------

/// A small text-input dialog used to add/rename sections and subsections.
Future<void> promptText(
  BuildContext context,
  String title,
  String hint,
  void Function(String value) onSubmit, {
  String initial = '',
}) async {
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: AppPalette.sheet,
      title: Text(title, style: TextStyle(color: AppPalette.inkPrimary)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(color: AppPalette.inkPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppPalette.inkSecondary),
        ),
        onSubmitted: (v) => Navigator.pop(dctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(context.t.cancel)),
        TextButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text),
            child: Text(context.t.save)),
      ],
    ),
  );
  if (result != null && result.trim().isNotEmpty) onSubmit(result.trim());
}

/// A compact label for a start–deadline span, or null when neither is set.
String? _dateSpanLabel(
    BuildContext context, DateTime? start, DateTime? deadline) {
  final df = DateFormat('MMM d, yyyy');
  if (start != null && deadline != null) {
    return '${DateFormat('MMM d').format(start)} – ${df.format(deadline)}';
  }
  if (start != null) return '${context.t.startShort}: ${df.format(start)}';
  if (deadline != null) return '${context.t.dueShort}: ${df.format(deadline)}';
  return null;
}

/// A little dialog with two date rows (start + deadline) — used to set the
/// span of a section or a task. Calls [onSave] with the chosen (nullable) dates.
Future<void> editDatesDialog(
  BuildContext context, {
  required DateTime? start,
  required DateTime? deadline,
  required void Function(DateTime? start, DateTime? deadline) onSave,
}) async {
  DateTime? s = start;
  DateTime? d = deadline;
  final now = DateTime.now();
  await showDialog<void>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setLocal) {
        Future<void> pickStart() async {
          final first = DateTime(now.year - 5);
          final last = d ?? now.add(const Duration(days: 365 * 10));
          var init = s ?? now;
          if (init.isBefore(first)) init = first;
          if (init.isAfter(last)) init = last;
          final p = await showDatePicker(
              context: dctx,
              initialDate: init,
              firstDate: first,
              lastDate: last);
          if (p != null) setLocal(() => s = p);
        }

        Future<void> pickDeadline() async {
          final floor = s ?? now;
          final last = floor.add(const Duration(days: 365 * 10));
          var init = d ?? floor.add(const Duration(days: 30));
          if (init.isBefore(floor)) init = floor;
          if (init.isAfter(last)) init = last;
          final p = await showDatePicker(
              context: dctx,
              initialDate: init,
              firstDate: floor,
              lastDate: last);
          if (p != null) setLocal(() => d = p);
        }

        return AlertDialog(
          backgroundColor: AppPalette.sheet,
          title: Text(context.t.datesSection,
              style: TextStyle(color: AppPalette.inkPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DateRow(
                  date: s,
                  placeholder: context.t.noStartDate,
                  icon: Icons.play_circle_outline_rounded,
                  onPick: pickStart,
                  onClear: () => setLocal(() => s = null),
                ),
                const SizedBox(height: 10),
                _DateRow(
                  date: d,
                  placeholder: context.t.noDeadline,
                  icon: Icons.event_outlined,
                  onPick: pickDeadline,
                  onClear: () => setLocal(() => d = null),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: Text(context.t.cancel)),
            TextButton(
                onPressed: () {
                  onSave(s, d);
                  Navigator.pop(dctx);
                },
                child: Text(context.t.save)),
          ],
        );
      },
    ),
  );
}

/// Adds a section in one step: a name field plus its start/deadline dates, so
/// there's no separate "Set dates" trip afterwards.
Future<void> promptNewSection(BuildContext context, String impulseId) async {
  final state = context.read<AppState>();
  final ctrl = TextEditingController();
  DateTime? s;
  DateTime? d;
  final now = DateTime.now();
  await showDialog<void>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setLocal) {
        Future<void> pickStart() async {
          final first = DateTime(now.year - 5);
          final last = d ?? now.add(const Duration(days: 365 * 10));
          var init = s ?? now;
          if (init.isBefore(first)) init = first;
          if (init.isAfter(last)) init = last;
          final p = await showDatePicker(
              context: dctx,
              initialDate: init,
              firstDate: first,
              lastDate: last);
          if (p != null) setLocal(() => s = p);
        }

        Future<void> pickDeadline() async {
          final floor = s ?? now;
          final last = floor.add(const Duration(days: 365 * 10));
          var init = d ?? floor.add(const Duration(days: 30));
          if (init.isBefore(floor)) init = floor;
          if (init.isAfter(last)) init = last;
          final p = await showDatePicker(
              context: dctx,
              initialDate: init,
              firstDate: floor,
              lastDate: last);
          if (p != null) setLocal(() => d = p);
        }

        return AlertDialog(
          backgroundColor: AppPalette.sheet,
          title: Text(context.t.addSection,
              style: TextStyle(color: AppPalette.inkPrimary)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: AppPalette.inkPrimary),
                  decoration: InputDecoration(
                    hintText: context.t.sectionHint,
                    hintStyle: TextStyle(color: AppPalette.inkSecondary),
                  ),
                ),
                const SizedBox(height: 16),
                _DateRow(
                  date: s,
                  placeholder: context.t.noStartDate,
                  icon: Icons.play_circle_outline_rounded,
                  onPick: pickStart,
                  onClear: () => setLocal(() => s = null),
                ),
                const SizedBox(height: 10),
                _DateRow(
                  date: d,
                  placeholder: context.t.noDeadline,
                  icon: Icons.event_outlined,
                  onPick: pickDeadline,
                  onClear: () => setLocal(() => d = null),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: Text(context.t.cancel)),
            TextButton(
                onPressed: () {
                  final title = ctrl.text.trim();
                  if (title.isEmpty) return;
                  state.addSection(impulseId, title,
                      startDate: s, deadline: d);
                  Navigator.pop(dctx);
                },
                child: Text(context.t.save)),
          ],
        );
      },
    ),
  );
}

/// The body of a long-term goal: the renameable daily-reminder list, then the
/// year sections (each a dropdown of subject subsections).
class _LongTermBody extends StatelessWidget {
  const _LongTermBody({required this.impulse, required this.editMode});
  final Impulse impulse;
  final bool editMode;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DailyReminderCard(impulse: impulse, date: today, editMode: editMode),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(context.t.sectionsHeader.toUpperCase(),
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.inkSecondary)),
        ),
        for (final s in impulse.sections) ...[
          _SectionTile(
              impulseId: impulse.id,
              section: s,
              date: today,
              editMode: editMode),
          const SizedBox(height: 10),
        ],
        if (editMode)
          _AddRow(
            label: context.t.addSection,
            onTap: () => promptNewSection(context, impulse.id),
          ),
      ],
    );
  }
}

/// The daily-reminder list (the goal's own flat threads) — a renameable
/// catch-all for anything outside the curriculum.
class _DailyReminderCard extends StatelessWidget {
  const _DailyReminderCard(
      {required this.impulse, required this.date, required this.editMode});
  final Impulse impulse;
  final DateTime date;
  final bool editMode;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final title = impulse.dailyReminderTitle.trim().isEmpty
        ? context.t.dailyReminder
        : impulse.dailyReminderTitle;
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surfaceGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  size: 18, color: Color(0xFFF5A623)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary)),
              ),
              if (editMode) ...[
                IconButton(
                  icon: Icon(Icons.edit_outlined,
                      size: 18, color: AppPalette.inkSecondary),
                  visualDensity: VisualDensity.compact,
                  tooltip: context.t.rename,
                  onPressed: () => promptText(
                      context, context.t.rename, context.t.dailyReminder,
                      (v) => state.renameDailyReminder(impulse.id, v),
                      initial: impulse.dailyReminderTitle),
                ),
                IconButton(
                  icon: Icon(Icons.add_rounded, color: AppPalette.inkPrimary),
                  visualDensity: VisualDensity.compact,
                  tooltip: context.t.newThread,
                  onPressed: () => openNewThread(context, impulse.id, date),
                ),
              ],
            ],
          ),
          if (impulse.threads.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TaskRowsList(
                impulseId: impulse.id,
                threads: impulse.threads,
                date: date,
                allowOpen: editMode,
                onReorder: editMode
                    ? (o, n) => state.reorderThread(impulse.id, o, n)
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A year (or any top-level section) — a dropdown of subject subsections.
class _SectionTile extends StatelessWidget {
  const _SectionTile(
      {required this.impulseId,
      required this.section,
      required this.date,
      required this.editMode});
  final String impulseId;
  final Section section;
  final DateTime date;
  final bool editMode;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.bubbleGlass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.cardOutline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () =>
                state.toggleSectionCollapsed(impulseId, section.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: section.collapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppPalette.inkSecondary),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          section.title.trim().isEmpty
                              ? context.t.untitledSection
                              : section.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.inkPrimary),
                        ),
                        if (_dateSpanLabel(
                                context, section.startDate, section.deadline)
                            case final span?) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_outlined,
                                  size: 12, color: AppPalette.inkSecondary),
                              const SizedBox(width: 4),
                              Text(span,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppPalette.inkSecondary)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text('${section.subsections.length}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.inkSecondary)),
                  if (editMode)
                    _rowMenu(
                      context,
                      onRename: () => promptText(
                          context, context.t.rename, context.t.sectionHint,
                          (v) => state.renameSection(impulseId, section.id, v),
                          initial: section.title),
                      onDates: () => editDatesDialog(
                        context,
                        start: section.startDate,
                        deadline: section.deadline,
                        onSave: (s, d) => state.setSectionDates(
                            impulseId, section.id,
                            start: s, deadline: d),
                      ),
                      onDelete: () =>
                          state.deleteSection(impulseId, section.id),
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          if (!section.collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: _SubsectionTree(
                  impulseId: impulseId,
                  section: section,
                  date: date,
                  editMode: editMode),
            ),
        ],
      ),
    );
  }
}

/// A subject (or any subsection) — a dropdown of its study threads.
/// The subsections of a section, drawn as a GitHub-README file tree in a
/// monospace "code block": ├──/└── connectors, collapsible subjects (▾/▸) and
/// [ ] / [x] task checkboxes. Retro on purpose, but every row is interactive —
/// tap a subject to fold it, tap a task to tick it, long-press to rename/edit.
class _SubsectionTree extends StatelessWidget {
  const _SubsectionTree(
      {required this.impulseId,
      required this.section,
      required this.date,
      required this.editMode});
  final String impulseId;
  final Section section;
  final DateTime date;
  final bool editMode;

  TextStyle get _base =>
      const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.5);

  @override
  Widget build(BuildContext context) {
    final dark = AppPalette.dark;
    // GitHub's own code-block palette (light: default, dark: dimmed).
    final codeBg = dark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA);
    final border = dark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
    final muted = dark ? const Color(0xFF8B949E) : const Color(0xFF6E7781);
    final ink = dark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
    final accent = dark ? const Color(0xFF58A6FF) : const Color(0xFF0969DA);
    final green = dark ? const Color(0xFF3FB950) : const Color(0xFF1A7F37);

    final rows = <Widget>[];
    for (final sub in section.subsections) {
      rows.add(_subLine(context, sub, muted: muted, ink: ink));
      if (!sub.collapsed) {
        for (final t in sub.threads) {
          rows.add(_taskLine(context, t,
              muted: muted, ink: ink, green: green));
        }
        if (editMode) {
          rows.add(_leaf(context, '│   └── ', '+ add task', accent, muted,
              onTap: () => _addTask(context, sub)));
        }
      }
    }
    if (editMode) {
      rows.add(_leaf(context, '└── ', '+ ${context.t.addSubsection}', accent,
          muted, onTap: () {
        final state = context.read<AppState>();
        promptText(context, context.t.addSubsection, context.t.subjectHint,
            (v) => state.addSubsection(impulseId, section.id, v));
      }));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _subLine(BuildContext context, Subsection sub,
      {required Color muted, required Color ink}) {
    final state = context.read<AppState>();
    final name =
        sub.title.trim().isEmpty ? context.t.untitledSection : sub.title;
    return InkWell(
      onTap: () =>
          state.toggleSubsectionCollapsed(impulseId, section.id, sub.id),
      onLongPress: !editMode
          ? null
          : () => _rowSheet(
        context,
        onRename: () => promptText(
            context, context.t.rename, context.t.subjectHint,
            (v) => state.renameSubsection(impulseId, section.id, sub.id, v),
            initial: sub.title),
        onDelete: () =>
            state.deleteSubsection(impulseId, section.id, sub.id),
      ),
      child: RichText(
        text: TextSpan(style: _base, children: [
          TextSpan(text: '├── ', style: TextStyle(color: muted)),
          TextSpan(
              text: sub.collapsed ? '▸ ' : '▾ ',
              style: TextStyle(color: muted)),
          TextSpan(
              text: name,
              style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
          if (sub.threads.isNotEmpty)
            TextSpan(
                text: '  (${sub.threads.length})',
                style: TextStyle(color: muted)),
        ]),
      ),
    );
  }

  Widget _taskLine(BuildContext context, Thread t,
      {required Color muted, required Color ink, required Color green}) {
    final state = context.read<AppState>();
    final imp = state.impulseById(impulseId);
    final dayKey = AppState.dayKeyFor(date);
    final done = imp?.threadDone(t, dayKey) ?? false;
    final title = t.title.trim().isEmpty ? context.t.untitledEntry : t.title;
    final time = t.reminderMinutes;
    // A Row (not one wrapping RichText) keeps the title in its own column: it
    // truncates instead of wrapping under the tree's vertical lines. A little
    // gap below sets each thread apart.
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: () => state.toggleThreadOn(impulseId, t.id, dayKey),
        onLongPress: !editMode
            ? null
            : () => showTaskDetailSheet(context, impulseId, t.id, date),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('│   ├── ', style: _base.copyWith(color: muted)),
            // A big, bold bracket so a task reads clearly apart from a subject.
            Text(done ? '[x] ' : '[ ] ',
                style: _base.copyWith(
                    color: done ? green : ink,
                    fontSize: 16,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700)),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _base.copyWith(
                    color: done ? muted : ink,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: muted),
              ),
            ),
            if (time != null)
              Text(' @ ${_hm(time)}', style: _base.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }

  Widget _leaf(BuildContext context, String prefix, String label, Color accent,
      Color muted,
      {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: RichText(
        text: TextSpan(style: _base, children: [
          TextSpan(text: prefix, style: TextStyle(color: muted)),
          TextSpan(text: label, style: TextStyle(color: accent)),
        ]),
      ),
    );
  }

  Future<void> _addTask(BuildContext context, Subsection sub) async {
    final state = context.read<AppState>();
    final id =
        await state.addBlankThreadToSubsection(impulseId, section.id, sub.id);
    if (id == null || !context.mounted) return;
    await showTaskDetailSheet(context, impulseId, id, date, isNew: true);
  }

  String _hm(int m) {
    final h = m ~/ 60, mm = m % 60;
    final ap = h < 12 ? 'am' : 'pm';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${mm.toString().padLeft(2, '0')}$ap';
  }
}

/// A rename/delete sheet shown on long-pressing a tree row.
Future<void> _rowSheet(BuildContext context,
    {required VoidCallback onRename, required VoidCallback onDelete}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: GlassPanel(
          borderRadius: 22,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading:
                    Icon(Icons.edit_outlined, color: AppPalette.inkPrimary),
                title: Text(context.t.rename),
                onTap: () {
                  Navigator.pop(context);
                  onRename();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: AppPalette.inkPrimary),
                title: Text(context.t.delete),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The overflow menu (rename / delete) on a section or subsection row.
Widget _rowMenu(BuildContext context,
    {required VoidCallback onRename,
    required VoidCallback onDelete,
    VoidCallback? onDates}) {
  return PopupMenuButton<String>(
    icon: Icon(Icons.more_vert_rounded,
        size: 20, color: AppPalette.inkSecondary),
    color: AppPalette.sheet,
    onSelected: (v) {
      switch (v) {
        case 'rename':
          onRename();
        case 'dates':
          onDates?.call();
        case 'delete':
          onDelete();
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(value: 'rename', child: Text(context.t.rename)),
      if (onDates != null)
        PopupMenuItem(value: 'dates', child: Text(context.t.setDates)),
      PopupMenuItem(value: 'delete', child: Text(context.t.delete)),
    ],
  );
}

/// A dashed "+ Add …" affordance.
class _AddRow extends StatelessWidget {
  const _AddRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppPalette.cardOutline,
              style: BorderStyle.solid,
              width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded,
                size: 18, color: AppPalette.inkSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.inkSecondary)),
          ],
        ),
      ),
    );
  }
}
