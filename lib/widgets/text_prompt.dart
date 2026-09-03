import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// A single-field text prompt whose controller lives on a [StatefulWidget], so
/// it is disposed only after the dialog unmounts.
///
/// Disposing a `TextEditingController` inline right after `showDialog` returns
/// races the route's exit animation — the field's `EditableText` still holds
/// the now-disposed controller, and the element teardown trips the framework's
/// `_dependents.isEmpty` assertion (a red-screen crash). Owning the controller
/// on a widget avoids both that crash and the leak of never disposing it.
///
/// Returns the entered text on confirm, or null when dismissed.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
  String? confirmLabel,
  TextCapitalization capitalization = TextCapitalization.sentences,
  TextInputType? keyboardType,
  int minLines = 1,
  int maxLines = 1,
  Widget? header,
  String? prefixText,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      hint: hint,
      initial: initial,
      confirmLabel: confirmLabel,
      capitalization: capitalization,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      header: header,
      prefixText: prefixText,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    this.hint,
    this.initial = '',
    this.confirmLabel,
    this.capitalization = TextCapitalization.sentences,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.header,
    this.prefixText,
  });

  final String title;
  final String? hint;
  final String initial;
  final String? confirmLabel;
  final TextCapitalization capitalization;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;
  final Widget? header;
  final String? prefixText;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _ctrl.text);

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _ctrl,
      autofocus: true,
      textCapitalization: widget.capitalization,
      keyboardType: widget.keyboardType,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixText: widget.prefixText,
      ),
      // Only single-line fields submit on the keyboard's done key.
      onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
    );
    return AlertDialog(
      title: Text(widget.title),
      content: widget.header == null
          ? field
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [widget.header!, const SizedBox(height: 12), field],
            ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t.cancel)),
        FilledButton(
            onPressed: _submit,
            child: Text(widget.confirmLabel ?? context.t.save)),
      ],
    );
  }
}
