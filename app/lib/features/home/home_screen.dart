// Pantalla posterior al login. Esta tarea (5) solo deja el destino de la
// navegación; la Tarea 6 le añade el botón "Nueva visita" y la Tarea 7 el
// botón "Sincronizar".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dependencies = ref.watch(appDependenciesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('VisitaCampo')),
      body: Center(
        child: Text('Sesión iniciada. Device: ${dependencies.deviceId}'),
      ),
    );
  }
}
