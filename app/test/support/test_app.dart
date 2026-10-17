import 'package:flutter/material.dart';
import 'package:visitacampo/l10n/l10n.dart';
import 'package:visitacampo/ui/theme/app_theme.dart';

/// Monta `home` con el mismo tema y los mismos textos que la app real
/// (`lib/main.dart`). Sin los delegados de localización, `context.l10n`
/// fallaría en cualquier pantalla.
Widget testApp(Widget home) {
  return MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
