// VisitaCampo — punto de entrada real (Tarea 5 del plan de despliegue del
// demo). Reemplaza el demo de `flutter create` (contador) sin modificar.
// Sin restauración de sesión al reiniciar: la app siempre arranca en
// LoginScreen (decisión de diseño de esta tarea — ver el plan).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_dependencies.dart';
import 'core/providers.dart';
import 'features/auth/login_screen.dart';
import 'l10n/l10n.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.bootstrap();
  runApp(
    ProviderScope(
      overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      // Tema claro u oscuro según el sistema: en campo, con sol directo o de
      // noche, el usuario elige lo que se lee mejor.
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const LoginScreen(),
    );
  }
}
