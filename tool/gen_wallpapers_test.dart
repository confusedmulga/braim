// Generates the four bundled "blooms" feed wallpapers (Material 3 Expressive
// style: organic blob masses with topographic ripple lines over a flat tone).
//
// Run manually when the art needs regenerating:
//   flutter test tool/gen_wallpapers_test.dart
//
// Output: assets/wallpapers/blooms_<name>.png (1080x2400).
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double kW = 1080;
const double kH = 2400;

class _Colorway {
  const _Colorway(this.name, this.base, this.blob, this.contour, this.accent);
  final String name;
  final Color base; // flat background
  final Color blob; // dark organic masses
  final Color contour; // ripple lines inside the masses
  final Color accent; // small light companion blobs
}

const _colorways = [
  _Colorway('green', Color(0xFF9CB878), Color(0xFF2F3F1D), Color(0xFF5C7440),
      Color(0xFFCBDfA8)),
  _Colorway('red', Color(0xFFD8907F), Color(0xFF5E1F14), Color(0xFF94473A),
      Color(0xFFF2C0AC)),
  _Colorway('blue', Color(0xFF82AACB), Color(0xFF16324E), Color(0xFF41678F),
      Color(0xFFBAD5EC)),
  _Colorway('black', Color(0xFF1A1B20), Color(0xFF08080B), Color(0xFF41434E),
      Color(0xFF2E3038)),
];

/// A smooth closed loop through [p] (Catmull-Rom converted to cubics).
Path _smoothClosed(List<Offset> p) {
  final n = p.length;
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = p[(i - 1 + n) % n];
    final p1 = p[i];
    final p2 = p[(i + 1) % n];
    final p3 = p[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

/// An organic blob: a wobbly circle of [points] radii seeded deterministically.
Path _blob(Offset c, double r, int seed, {int points = 9, double wobble = .42}) {
  final rnd = Random(seed);
  final pts = <Offset>[
    for (var i = 0; i < points; i++)
      c +
          Offset(cos(2 * pi * i / points), sin(2 * pi * i / points)) *
              (r * (1 - wobble / 2 + rnd.nextDouble() * wobble)),
  ];
  return _smoothClosed(pts);
}

Path _scaledAbout(Path src, Offset center, double s) {
  final m = Matrix4.identity()
    ..translateByDouble(center.dx, center.dy, 0, 1)
    ..scaleByDouble(s, s, 1, 1)
    ..translateByDouble(-center.dx, -center.dy, 0, 1);
  return src.transform(m.storage);
}

void _mass(Canvas canvas, _Colorway c, Offset center, double r, int seed) {
  final shape = _blob(center, r, seed);
  canvas.drawPath(shape, Paint()..color = c.blob);
  // Topographic ripples: shrinking echoes of the same outline.
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.5
    ..color = c.contour;
  for (var s = 0.9; s > 0.12; s -= 0.085) {
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(_scaledAbout(shape, center, s), line);
    canvas.restore();
  }
}

Future<void> _render(_Colorway c, String outPath) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, kW, kH));
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, kW, kH), Paint()..color = c.base);

  // Light companion blobs first so the dark masses overlap them.
  canvas.drawPath(
      _blob(const Offset(kW * .18, kH * .38), kW * .30, 11),
      Paint()..color = c.accent);
  canvas.drawPath(
      _blob(const Offset(kW * .88, kH * .70), kW * .24, 12),
      Paint()..color = c.accent);

  // Two large rippled masses anchored partially offscreen.
  _mass(canvas, c, const Offset(kW * .84, kH * .16), kW * .78, 1);
  _mass(canvas, c, const Offset(kW * .08, kH * .86), kW * .66, 2);
  // A mid-field smaller one for rhythm.
  _mass(canvas, c, const Offset(kW * .30, kH * .58), kW * .20, 3);

  final img = await rec.endRecording().toImage(kW.toInt(), kH.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File(outPath).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate blooms wallpapers', () async {
    final dir = Directory('assets/wallpapers');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    for (final c in _colorways) {
      await _render(c, 'assets/wallpapers/blooms_${c.name}.png');
    }
  });
}
