import 'package:flutter/material.dart';

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
  });

  final String? asset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (asset == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.white),
          child,
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(asset!, fit: BoxFit.cover),
        ColoredBox(color: Colors.white.withValues(alpha: 0.68)),
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
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text('Note background',
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
        child: const Icon(Icons.format_color_reset_rounded,
            color: AppPalette.inkSecondary),
      ),
    );
  }
}
