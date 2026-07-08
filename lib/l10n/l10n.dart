import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

/// Shorthand: `context.t.someString`.
extension L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this);
}
