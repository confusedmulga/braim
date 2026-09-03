import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_chrome.dart';

/// Book-wide find & replace: searches every manuscript page's title and body,
/// shows a live match count, and rewrites all occurrences in one pass. Workshop
/// notes are never touched — only the manuscript.
class BookFindReplaceScreen extends StatefulWidget {
  const BookFindReplaceScreen({super.key, required this.bookId});

  final String bookId;

  @override
  State<BookFindReplaceScreen> createState() => _BookFindReplaceScreenState();
}

class _BookFindReplaceScreenState extends State<BookFindReplaceScreen> {
  final _find = TextEditingController();
  final _replace = TextEditingController();
  bool _caseSensitive = false;
  bool _working = false;

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final query = _find.text;
    final matches = query.isEmpty
        ? 0
        : state.bookFindMatches(widget.bookId, query,
            caseSensitive: _caseSensitive);

    return FrostedScaffold(
      title: context.t.findAndReplace,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
        children: [
            TextField(
              controller: _find,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.t.findLabel,
                prefixIcon: const Icon(Icons.search_rounded),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _replace,
              decoration: InputDecoration(
                labelText: context.t.replaceWithLabel,
                prefixIcon: const Icon(Icons.edit_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _caseSensitive,
              onChanged: (v) => setState(() => _caseSensitive = v),
              title: Text(context.t.caseSensitive),
            ),
            const SizedBox(height: 2),
            Text(
              query.isEmpty ? '' : context.t.matchesFound(matches),
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.inkSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: (query.isEmpty || matches == 0 || _working)
                  ? null
                  : () => _replaceAll(context, matches),
              icon: const Icon(Icons.done_all_rounded, size: 20),
              label: Text(context.t.replaceAll),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
    );
  }

  Future<void> _replaceAll(BuildContext context, int matches) async {
    // Replacing rewrites the manuscript in place with no per-book undo, so
    // confirm first.
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.t.replaceAll),
        content: Text(context.t.replaceAllConfirm(matches)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t.replaceAll)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final t = context.t;
    setState(() => _working = true);
    final count = await context.read<AppState>().bookReplaceAll(
        widget.bookId, _find.text, _replace.text,
        caseSensitive: _caseSensitive);
    if (!mounted) return;
    setState(() => _working = false);
    messenger.showSnackBar(SnackBar(content: Text(t.replacedCount(count))));
    navigator.pop();
  }
}
