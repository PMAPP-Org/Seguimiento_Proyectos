// Punto de entrada de los textos de la app. `app_localizations.dart` lo genera
// `flutter gen-l10n` desde `app_es.arb` (no se versiona, igual que *.g.dart).
import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// `context.l10n.loginSubmit` en vez de `AppLocalizations.of(context).loginSubmit`.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
