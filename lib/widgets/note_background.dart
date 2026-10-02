import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

/// Background for the opened note: its colour tag, or the plain sheet colour.
class NoteBackground extends StatelessWidget {
  const NoteBackground({super.key, required this.child, this.color});

  /// Optional note colour tag; null shows the plain sheet colour.
  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: color ?? AppPalette.sheet),
        child,
      ],
    );
  }
}

/// A bottom sheet of colour swatches for a note. Each tap is applied live
/// through [onColor] and the sheet stays open.
Future<void> showNoteStylePicker(
  BuildContext context, {
  required int? currentColor,
  required ValueChanged<int?> onColor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) =>
        _NoteStyleSheet(currentColor: currentColor, onColor: onColor),
  );
}

class _NoteStyleSheet extends StatefulWidget {
  const _NoteStyleSheet({required this.currentColor, required this.onColor});

  final int? currentColor;
  final ValueChanged<int?> onColor;

  @override
  State<_NoteStyleSheet> createState() => _NoteStyleSheetState();
}

class _NoteStyleSheetState extends State<_NoteStyleSheet> {
  late int? _color = widget.currentColor;

  void _selectColor(int? value) {
    setState(() => _color = value);
    widget.onColor(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassEdge(
        borderRadius: 28,
        fill: AppPalette.whiteFill,
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
                _ColorDot(
                  color: null,
                  selected: _color == null,
                  onTap: () => _selectColor(null),
                ),
                for (final c in NoteColors.swatches)
                  _ColorDot(
                    color: Color(c),
                    selected: _color == c,
                    onTap: () => _selectColor(c),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(
      {required this.color, required this.selected, required this.onTap});
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
}
