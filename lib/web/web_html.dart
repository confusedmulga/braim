// Braim Web HTML building blocks. Every string that reaches HTML goes through
// [esc]; there is no template library. See docs/braim-web-plan.md, section 5.5.

import 'dart:convert';

import 'web_assets.dart';

/// Escapes [s] for HTML text and for quoted attribute values.
String esc(String s) => const HtmlEscape().convert(s);

/// A whole page: the head with the stylesheet, the deferred script and, for a
/// signed-in browser, the CSRF token; then [body]. [body] must already be
/// escaped.
String htmlPage({
  required WebAssets assets,
  required String title,
  required String body,
  String? csrf,
  String bodyClass = '',
}) {
  final out = StringBuffer()
    ..write('<!doctype html>\n<html lang="en">\n<head>\n')
    ..write('<meta charset="utf-8">\n')
    ..write(
      '<meta name="viewport" '
      'content="width=device-width, initial-scale=1">\n',
    )
    ..write('<meta name="color-scheme" content="light dark">\n');
  if (csrf != null) {
    out.write('<meta name="braim-csrf" content="${esc(csrf)}">\n');
  }
  out
    ..write('<title>${esc(title)}</title>\n')
    ..write('<link rel="stylesheet" href="${esc(assets.url('app.css'))}">\n')
    ..write('<script src="${esc(assets.url('app.js'))}" defer></script>\n')
    ..write('</head>\n')
    ..write(
      bodyClass.isEmpty ? '<body>\n' : '<body class="${esc(bodyClass)}">\n',
    )
    ..write(body)
    ..write('\n</body>\n</html>\n');
  return out.toString();
}
