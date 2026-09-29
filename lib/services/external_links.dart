import 'package:url_launcher/url_launcher.dart';

/// [raw] with a scheme: an address typed or pasted bare (`example.com/page`,
/// `x.com/jack/status/20`) gets `https://`. One that already has one — any
/// `scheme://`, or `mailto:` / `tel:` / `sms:` — is kept as it is. Empty in,
/// empty out.
String withUrlScheme(String raw) {
  final u = raw.trim();
  if (u.isEmpty) return u;
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(u) ||
      RegExp(r'^(mailto|tel|sms):', caseSensitive: false).hasMatch(u)) {
    return u;
  }
  return 'https://$u';
}

/// Opens [url] outside Braim, in whichever app handles it (the browser,
/// YouTube, X…). A bare address gets `https://` first ([withUrlScheme]).
/// Returns whether something opened it; never throws.
Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(withUrlScheme(url));
  if (uri == null || uri.toString().isEmpty) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
