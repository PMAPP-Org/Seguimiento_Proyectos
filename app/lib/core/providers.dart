// Único punto de acceso a `AppDependencies` desde los widgets (Tarea 5 del
// plan de despliegue del demo). `main()` sobrescribe este provider con la
// instancia real construida por `AppDependencies.bootstrap()`; los tests de
// widgets lo sobrescriben con una instancia armada con fakes (mismo patrón
// en `test/features/auth/login_screen_test.dart`).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_dependencies.dart';

final appDependenciesProvider = Provider<AppDependencies>((ref) {
  throw UnimplementedError(
    'appDependenciesProvider debe sobrescribirse en main() (o en el ProviderScope '
    'de un test) con la instancia ya construida por AppDependencies.bootstrap().',
  );
});
