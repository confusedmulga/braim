import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../theme/app_theme.dart';

/// A compact, deliberately-narrow liquid-glass search field (same glass as the
/// navigation island). [widthFactor] keeps it less wide than the full screen.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.widthFactor = 0.74,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: widthFactor,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: FakeGlass(
            shape: const LiquidRoundedSuperellipse(borderRadius: 22),
            settings: const LiquidGlassSettings(
              glassColor: Color(0xA6FFFFFF),
              blur: 14,
            ),
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        size: 18, color: AppPalette.inkSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        onChanged: onChanged,
                        style: const TextStyle(
                            fontSize: 14, color: AppPalette.inkPrimary),
                        cursorColor: AppPalette.inkPrimary,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: hint,
                          hintStyle: const TextStyle(
                              fontSize: 14, color: AppPalette.inkSecondary),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}
