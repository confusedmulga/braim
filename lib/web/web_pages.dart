// Braim Web page builders. Each returns finished HTML; strings come from the
// app's localizations and pass through [esc]. See docs/braim-web-plan.md,
// section 8.3.

import '../l10n/l10n.dart';
import 'web_assets.dart';
import 'web_html.dart';

/// The pairing form: six single-digit boxes that `app.js` fills, advances and
/// submits to `/api/pair`.
String pairPage(AppLocalizations l10n, WebAssets assets) {
  final digits = StringBuffer();
  for (var i = 0; i < 6; i++) {
    digits.write(
      '<input class="digit" type="text" inputmode="numeric" '
      'maxlength="1" pattern="[0-9]" '
      'autocomplete="${i == 0 ? 'one-time-code' : 'off'}" '
      'aria-label="${esc('${l10n.webCodeLabel} ${i + 1}')}">',
    );
  }
  final body =
      '''
<main class="pair">
<h1>${esc(l10n.webPairTitle)}</h1>
<p class="muted">${esc(l10n.webPairHelp)}</p>
<form id="pair-form" data-offline="${esc(l10n.webOffline)}" novalidate>
<fieldset>
<legend>${esc(l10n.webCodeLabel)}</legend>
<div class="digits">$digits</div>
</fieldset>
<p class="msg" id="pair-msg" role="alert"></p>
<button type="submit" class="primary">${esc(l10n.webPairLink)}</button>
</form>
<p class="muted small">${esc(l10n.webPairNewAddress)}</p>
</main>''';
  return htmlPage(
    assets: assets,
    title: l10n.webPairTitle,
    body: body,
    bodyClass: 'bare',
  );
}

/// The top bar every signed-in page shares.
String topBar(AppLocalizations l10n) =>
    '''
<header class="bar">
<a class="brand" href="/">${esc(l10n.appTitle)}</a>
<button type="button" class="quiet" data-action="logout">${esc(l10n.webLogOut)}</button>
</header>''';

/// The signed-in home page until the notes feed exists (Phase 3).
String homePlaceholderPage(
  AppLocalizations l10n,
  WebAssets assets,
  String csrf,
) {
  final body =
      '''
${topBar(l10n)}
<main class="narrow">
<p>${esc(l10n.webLinkedPlaceholder)}</p>
</main>''';
  return htmlPage(
    assets: assets,
    title: l10n.webSection,
    body: body,
    csrf: csrf,
  );
}

/// A plain error page: a heading and a link home. Never a stack trace.
String errorPage(AppLocalizations l10n, WebAssets assets, String message) {
  final body =
      '''
<main class="narrow error">
<h1>${esc(message)}</h1>
<p><a href="/">${esc(l10n.appTitle)}</a></p>
</main>''';
  return htmlPage(
    assets: assets,
    title: message,
    body: body,
    bodyClass: 'bare',
  );
}
