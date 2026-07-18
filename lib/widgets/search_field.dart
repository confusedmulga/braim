import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// A compact, deliberately-narrow search field (same flat near-opaque surface
/// as the navigation island). [widthFactor] keeps it less wide than the full
/// screen. Shows a clear ✕ on the right whenever there is text.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.widthFactor = 0.74,
    this.trailing,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final double widthFactor;

  /// Optional action shown in the empty space to the right of the field
  /// (e.g. the feed sort button).
  final Widget? trailing;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _clear() {
    _ctrl.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // No bottom padding: the gap below the bar belongs to the feeds' top
      // padding, so their fade band starts flush at the bar's edge.
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      child: Row(
        children: [
          Expanded(
            child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: widget.widthFactor,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: AppPalette.bubbleGlass,
              border: Border.all(color: AppPalette.cardOutline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded,
                        size: 18, color: AppPalette.inkSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        onChanged: (v) {
                          widget.onChanged(v);
                          // Rebuild so the clear button tracks the text.
                          setState(() {});
                        },
                        style: TextStyle(
                            fontSize: 14, color: AppPalette.inkPrimary),
                        cursorColor: AppPalette.inkPrimary,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: widget.hint,
                          hintStyle: TextStyle(
                              fontSize: 14, color: AppPalette.inkSecondary),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    if (_ctrl.text.isNotEmpty)
                      Semantics(
                        button: true,
                        label: context.t.clearSearch,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _clear,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(Icons.close_rounded,
                                size: 17, color: AppPalette.inkSecondary),
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
          if (widget.trailing != null) ...[
            const SizedBox(width: 10),
            widget.trailing!,
          ],
        ],
      ),
    );
  }
}
