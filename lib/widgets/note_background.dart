import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

/// The note background images the user can choose from (BACK05 is intentionally
/// absent from the asset set).
const List<String> kNoteBackgrounds = [
  'assets/BACK01.jpg',
  'assets/BACK02.jpg',
  'assets/BACK03.jpg',
  'assets/BACK04.jpg',
  'assets/BACK06.jpg',
  'assets/BACK07.jpg',
  'assets/BACK08.jpg',
  'assets/BACK09.jpg',
  'assets/BACK10.jpg',
  'assets/BACK11.jpg',
  'assets/BACK12.jpg',
];

/// Background for the opened note. With no [asset] it's plain white; with one
/// it shows the image under a whitish tint so black text stays legible.
///
/// Deliberately no backdrop blur here: a full-screen BackdropFilter re-samples
/// every frame of the open/close morph (stutter), and dropping it mid-close
/// caused a visible flash. A constant tint looks the same at rest and is free.
class NoteBackground extends StatelessWidget {
  const NoteBackground({
    super.key,
    required this.asset,
    required this.child,
    this.color,
  });

  final String? asset;

  /// Optional note colour tag; used as the flat background when no [asset] is
  /// set (an asset takes precedence).
  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (asset == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: color ?? AppPalette.sheet),
          child,
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // Decode at screen size: the BACK assets are multi-thousand-pixel
        // JPGs, and a full-res decode made themed notes visibly laggy (a
        // huge texture rescaled every frame of the open/close morph).
        Image.asset(asset!, fit: BoxFit.cover, cacheWidth: 1440),
        ColoredBox(color: AppPalette.noteTint),
        child,
      ],
    );
  }
}

/// Bottom sheet to pick a note background. Returns the asset path, the sentinel
/// `'__none__'` for plain white, or null if dismissed.
Future<String?> showNoteBackgroundPicker(
  BuildContext context, {
  required String? current,
}) {
  return showModalBottomSheet<String?>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Padding(
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
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(context.t.noteBackground,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppPalette.inkPrimary)),
            ),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                _SwatchNone(
                  selected: current == null,
                  onTap: () => Navigator.pop(context, '__none__'),
                ),
                for (final a in kNoteBackgrounds)
                  _Swatch(
                    asset: a,
                    selected: current == a,
                    onTap: () => Navigator.pop(context, a),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.asset, required this.selected, required this.onTap});
  final String asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppPalette.inkPrimary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(asset, fit: BoxFit.cover, cacheWidth: 220),
        ),
      ),
    );
  }
}

class _SwatchNone extends StatelessWidget {
  const _SwatchNone({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppPalette.inkPrimary : Colors.black12,
            width: 2.5,
          ),
        ),
        child: Icon(Icons.format_color_reset_rounded,
            color: AppPalette.inkSecondary),
      ),
    );
  }
}


/// Bottom sheet to pick a note colour tag. Returns the swatch ARGB int,
/// [NoteColors.none] to clear it, or null if dismissed.
Future<int?> showNoteColorPicker(
  BuildContext context, {
  required int? current,
}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Padding(
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
                      fontWeight: FontWeight.w800,
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
                  selected: current == null,
                  onTap: () => Navigator.pop(context, NoteColors.none),
                ),
                for (final c in NoteColors.swatches)
                  _ColorDot(
                    color: Color(c),
                    selected: current == c,
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
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
