// Pantalla posterior al login. La Tarea 6 añade "Nueva visita"; la Tarea 7
// añade "Sincronizar".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../capture/capture_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dependencies = ref.watch(appDependenciesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('VisitaCampo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Sesión iniciada. Device: ${dependencies.deviceId}'),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const Key('home_new_visit_button'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CaptureScreen()),
                );
              },
              child: const Text('Nueva visita'),
            ),
          ],
        ),
      ),
    );
  }
}
