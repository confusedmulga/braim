import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// Opens the in-app cropper for the image at [sourcePath] and returns the path
/// of the image to use: a freshly saved crop, [sourcePath] itself when the
/// user keeps the Original, or null if they backed out (in which case the
/// caller should keep the original too). [aspectRatio] (width / height) seeds
/// a fixed crop shape — e.g. 2/3 for a book cover; null opens on Original.
Future<String?> cropImageFile(
  BuildContext context,
  String sourcePath, {
  double? aspectRatio,
}) async {
  Uint8List bytes;
  try {
    bytes = await File(sourcePath).readAsBytes();
  } catch (_) {
    return null;
  }
  if (!context.mounted) return null;
  final cropped = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CropScreen(image: bytes, aspectRatio: aspectRatio),
    ),
  );
  if (cropped == null) return null;
  // Original hands back the very bytes it was given: keep the file as it is,
  // with no re-encode.
  if (identical(cropped, bytes)) return sourcePath;
  return StorageService.instance.saveImageBytes(cropped);
}

/// A full-screen, in-app image cropper. Pop returns the cropped bytes
/// ([Uint8List]) on confirm — [image] itself when Original is chosen — or
/// null on cancel.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.image, this.aspectRatio});

  final Uint8List image;
  final double? aspectRatio;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _controller = CropController();
  late double? _ratio = widget.aspectRatio;

  /// Original: the picture goes in uncropped. Where it opens unless a crop
  /// shape was asked for (a book cover asks for 2:3).
  late bool _original = widget.aspectRatio == null;
  bool _busy = false;

  /// Whether the cropper has finished preparing the picture. Until then it
  /// must not be given commands (the package throws), so a shape chosen
  /// meanwhile waits in [_ratioPending] and ✓ waits too.
  bool _cropReady = false;
  bool _ratioPending = false;

  void _choose({required bool original, double? ratio}) {
    // The cropper only exists while a crop shape is chosen. Coming from
    // Original it is built fresh with the new shape; the controller is not
    // connected to anything until then.
    final cropperShown = !_original;
    setState(() {
      _original = original;
      _ratio = ratio;
    });
    if (original) {
      _cropReady = false;
      _ratioPending = false;
    } else if (cropperShown) {
      if (_cropReady) {
        _controller.aspectRatio = ratio;
      } else {
        _ratioPending = true;
      }
    }
  }

  void _onCropStatus(CropStatus status) {
    _cropReady = status == CropStatus.ready;
    if (_cropReady && _ratioPending) {
      _ratioPending = false;
      _controller.aspectRatio = _ratio;
    }
  }

  void _confirm() {
    if (_original) {
      Navigator.of(context).pop(widget.image);
      return;
    }
    if (!_cropReady) return;
    setState(() => _busy = true);
    _controller.crop();
  }

  void _onCropped(CropResult result) {
    if (!mounted) return;
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(croppedImage);
      case CropFailure():
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.somethingWrong)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Inset the picture from the screen's edges: room around the corner
    // handles, and dragging one never starts in Android's back-swipe zone.
    final gestures = MediaQuery.systemGestureInsetsOf(context);
    final left = math.max(28.0, gestures.left + 12);
    final right = math.max(28.0, gestures.right + 12);
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: 54,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white),
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          context.t.cropTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_rounded,
                            color: Colors.white),
                        onPressed: _busy ? null : _confirm,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(left, 20, right, 8),
                    child: _original
                        ? Center(
                            child: Image.memory(
                              widget.image,
                              fit: BoxFit.contain,
                              // Decoded at screen size: a preview needs no
                              // more, and a camera photo at full size is tens
                              // of megabytes of memory.
                              cacheWidth:
                                  (media.size.width * media.devicePixelRatio)
                                      .round(),
                            ),
                          )
                        : Crop(
                            image: widget.image,
                            controller: _controller,
                            aspectRatio: _ratio,
                            baseColor: Colors.black,
                            maskColor: Colors.black.withValues(alpha: 0.55),
                            interactive: true,
                            cornerDotBuilder: (size, edge) =>
                                const DotControl(color: Colors.white),
                            onCropped: _onCropped,
                            onStatusChanged: _onCropStatus,
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  // Wraps onto a second line on a narrow phone.
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    runSpacing: 10,
                    children: [
                      _chip(context.t.cropOriginal, _original,
                          () => _choose(original: true)),
                      _ratioChip(context.t.cropFreeform, null),
                      _ratioChip(context.t.cropSquare, 1),
                      _ratioChip('3:4', 3 / 4),
                      _ratioChip('2:3', 2 / 3),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ratioChip(String label, double? ratio) => _chip(
        label,
        !_original && _ratio == ratio,
        () => _choose(original: false, ratio: ratio),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppPalette.scheme.primary : Colors.white12,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppPalette.scheme.onPrimary : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
