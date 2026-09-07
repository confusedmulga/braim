import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// Opens the in-app cropper for the image at [sourcePath] and returns the path
/// of a freshly saved cropped image, or null if the user backed out (in which
/// case the caller should keep the original). [aspectRatio] (width / height)
/// seeds a fixed crop shape — e.g. 2/3 for a book cover; null starts free-form.
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
  return StorageService.instance.saveImageBytes(cropped);
}

/// A full-screen, in-app image cropper. Pop returns the cropped bytes
/// ([Uint8List]) on confirm, or null on cancel.
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
  bool _busy = false;

  void _setRatio(double? r) {
    setState(() => _ratio = r);
    _controller.aspectRatio = r;
  }

  void _confirm() {
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
                  child: Crop(
                    image: widget.image,
                    controller: _controller,
                    aspectRatio: _ratio,
                    baseColor: Colors.black,
                    maskColor: Colors.black.withValues(alpha: 0.55),
                    interactive: true,
                    cornerDotBuilder: (size, edge) =>
                        const DotControl(color: Colors.white),
                    onCropped: _onCropped,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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

  Widget _ratioChip(String label, double? ratio) {
    final selected = _ratio == ratio;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: GestureDetector(
        onTap: () => _setRatio(ratio),
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
