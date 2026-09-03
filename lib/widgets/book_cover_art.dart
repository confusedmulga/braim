import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/book.dart';

/// A generated book cover for books without a photo: a deterministic colour
/// palette and a subtle geometric pattern, with the title (in the book's own
/// typeface) and author typeset over it. Every book gets a distinct, tasteful
/// cover for free — no photo needed.
class BookCoverArt extends StatelessWidget {
  const BookCoverArt({super.key, required this.book, this.compact = false});

  final Book book;

  /// A small shelf tile (title along the bottom) vs. the large opened-book
  /// cover (centered title, author and rule).
  final bool compact;

  /// A stable seed per book, so its cover never changes between launches.
  int get _seed => book.id.hashCode & 0x7fffffff;

  static const List<List<Color>> _palettes = [
    [Color(0xFF7B4B94), Color(0xFF3A2450)], // plum
    [Color(0xFF1F6F6B), Color(0xFF0E3A38)], // teal
    [Color(0xFF9C4A2E), Color(0xFF54221A)], // rust
    [Color(0xFF3C6B4A), Color(0xFF1C3A28)], // forest
    [Color(0xFF3B4A8C), Color(0xFF222A54)], // indigo
    [Color(0xFF8C2E4A), Color(0xFF491728)], // wine
    [Color(0xFF465569), Color(0xFF232B36)], // slate
    [Color(0xFF8A6B2E), Color(0xFF463618)], // amber
    [Color(0xFF2E5A8C), Color(0xFF17304A)], // ocean
    [Color(0xFF5A467F), Color(0xFF2C2247)], // violet
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[_seed % _palettes.length];
    final pattern = _seed ~/ _palettes.length % 4;
    final title = book.title.trim().isEmpty ? context.t.untitledBook : book.title;
    final author = book.author.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0;
        final pad = w * (compact ? 0.11 : 0.12);
        final titleSize = (w * (compact ? 0.135 : 0.115)).clamp(13.0, 34.0);
        final authorSize = (w * 0.055).clamp(8.0, 15.0);

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The subtle pattern, painted in faint ink over the gradient.
              CustomPaint(painter: _CoverPatternPainter(pattern)),
              // A soft vignette so type stays legible against the pattern.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x22000000), Color(0x55000000)],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(pad),
                child: compact
                    ? _compactType(title, titleSize)
                    : _fullType(title, author, titleSize, authorSize),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _compactType(String title, double titleSize) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        title,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: book.fontFamily,
          fontSize: titleSize,
          height: 1.12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _fullType(
      String title, String author, double titleSize, double authorSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(flex: 2),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: book.fontFamily,
            fontSize: titleSize,
            height: 1.14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        SizedBox(height: titleSize * 0.5),
        Container(
          width: titleSize * 1.6,
          height: 1.5,
          color: Colors.white.withValues(alpha: 0.55),
        ),
        const Spacer(flex: 3),
        if (author.isNotEmpty)
          Text(
            author.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: book.fontFamily,
              fontSize: authorSize,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
      ],
    );
  }
}

/// Paints one of a few faint geometric patterns over the cover gradient.
class _CoverPatternPainter extends CustomPainter {
  _CoverPatternPainter(this.variant);
  final int variant;

  static const _ink = Color(0x14FFFFFF); // ~8% white

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    switch (variant) {
      case 0:
        // Diagonal hairlines.
        final step = size.width / 7;
        for (var x = -size.height; x < size.width; x += step) {
          canvas.drawLine(
              Offset(x, 0), Offset(x + size.height, size.height), paint);
        }
      case 1:
        // Concentric arcs radiating from the top-right corner.
        final center = Offset(size.width, 0);
        final maxR = size.height * 1.5;
        final step = maxR / 9;
        for (var r = step; r < maxR; r += step) {
          canvas.drawCircle(center, r, paint);
        }
      case 2:
        // A grid of small dots.
        final dot = Paint()..color = _ink;
        final step = size.width / 6;
        for (var y = step / 2; y < size.height; y += step) {
          for (var x = step / 2; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), 1.6, dot);
          }
        }
      default:
        // Faint horizontal rules, ledger-like.
        final step = size.height / 14;
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
    }
  }

  @override
  bool shouldRepaint(_CoverPatternPainter old) => old.variant != variant;
}
