import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Where a new circuit note goes, and what kind it is — the result of the
/// note screen's **+** sheet.
class CircuitAddChoice {
  const CircuitAddChoice({required this.under, required this.markdown});

  /// true = under this note (a child); false = next to it (a sibling).
  final bool under;
  final bool markdown;
}

/// The sheet a note's **+** button opens: place a new note next to or under
/// this one, as a rich note or a Markdown note. On the first note only "under"
/// applies (a first note has no siblings), so [rootOnly] hides the sibling row.
/// Returns null if dismissed.
Future<CircuitAddChoice?> showCircuitAddSheet(
  BuildContext context, {
  required bool rootOnly,
}) {
  return showModalBottomSheet<CircuitAddChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          strong: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.t.circuitAddTitle,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.inkPrimary),
                  ),
                ),
              ),
              if (!rootOnly)
                _tile(sheetCtx, Icons.arrow_forward_rounded,
                    context.t.circuitAddSibling,
                    const CircuitAddChoice(under: false, markdown: false)),
              _tile(sheetCtx, Icons.subdirectory_arrow_right_rounded,
                  context.t.circuitAddChild,
                  const CircuitAddChoice(under: true, markdown: false)),
              _tile(sheetCtx, Icons.data_object_rounded,
                  context.t.circuitAddChildMarkdown,
                  const CircuitAddChoice(under: true, markdown: true)),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _tile(
  BuildContext ctx,
  IconData icon,
  String label,
  CircuitAddChoice choice,
) =>
    ListTile(
      leading: Icon(icon, color: AppPalette.inkSecondary),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600, color: AppPalette.inkPrimary)),
      onTap: () => Navigator.pop(ctx, choice),
    );
