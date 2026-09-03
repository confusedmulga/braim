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

/// One bottom sheet to style a note: the colour swatches sit at the top and the
/// background images below, so both live in a single menu. Each tap is applied
/// live through [onColor] / [onBackground] and the sheet stays open, so a
/// colour and a background can be chosen in one visit.
Future<void> showNoteStylePicker(
  BuildContext context, {
  required int? currentColor,
  required String? currentBackground,
  required ValueChanged<int?> onColor,
  required ValueChanged<String?> onBackground,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _NoteStyleSheet(
      currentColor: currentColor,
      currentBackground: currentBackground,
      onColor: onColor,
      onBackground: onBackground,
    ),
  );
}

class _NoteStyleSheet extends StatefulWidget {
  const _NoteStyleSheet({
    required this.currentColor,
    required this.currentBackground,
    required this.onColor,
    required this.onBackground,
  });

  final int? currentColor;
  final String? currentBackground;
  final ValueChanged<int?> onColor;
  final ValueChanged<String?> onBackground;

  @override
  State<_NoteStyleSheet> createState() => _NoteStyleSheetState();
}

class _NoteStyleSheetState extends State<_NoteStyleSheet> {
  late int? _color = widget.currentColor;
  late String? _background = widget.currentBackground;

  void _selectColor(int? value) {
    setState(() => _color = value);
    widget.onColor(value);
  }

  void _selectBackground(String? value) {
    setState(() => _background = value);
    widget.onBackground(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassEdge(
        borderRadius: 28,
        fill: AppPalette.whiteFill,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Colours first…
                _header(context.t.noteColor),
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
                const SizedBox(height: 18),
                // …then the backgrounds beneath them.
                _header(context.t.noteBackground),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    _SwatchNone(
                      selected: _background == null,
                      onTap: () => _selectBackground(null),
                    ),
                    for (final a in kNoteBackgrounds)
                      _Swatch(
                        asset: a,
                        selected: _background == a,
                        onTap: () => _selectBackground(a),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppPalette.inkPrimary)),
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
