import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// A non-editable info block for a node's overflow menu: when it was created,
/// when it was last modified, and its character count. Shared by the rich and
/// Markdown editors so both read the same way.
Widget noteInfoBlock(
  BuildContext context, {
  required DateTime created,
  required DateTime modified,
  required int charCount,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(context, Icons.event_outlined, context.t.infoCreated,
            _stamp(created)),
        const SizedBox(height: 9),
        _row(context, Icons.edit_calendar_outlined, context.t.infoModified,
            _stamp(modified)),
        const SizedBox(height: 9),
        _row(context, Icons.notes_rounded, context.t.infoCharacters,
            _grouped(charCount)),
      ],
    ),
  );
}

Widget _row(BuildContext context, IconData icon, String label, String value) {
  return Row(
    children: [
      Icon(icon, size: 17, color: AppPalette.inkSecondary),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(fontSize: 13, color: AppPalette.inkSecondary)),
      const Spacer(),
      Text(value,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppPalette.inkPrimary)),
    ],
  );
}

/// "5 Sep 2026, 14:03" — an unambiguous, locale-neutral stamp.
String _stamp(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, ${two(d.hour)}:${two(d.minute)}';
}

/// Groups thousands with commas ("12,345") without pulling in intl.
String _grouped(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
