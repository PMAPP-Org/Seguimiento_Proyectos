// Pantalla posterior al login. Botón "Nueva visita" (Tarea 6) + "Sincronizar"
// (Tarea 7 del plan de despliegue del demo): dispara, en orden,
// `drainOutbox()` (push del outbox de visitas), `drainPending()` (subida de
// adjuntos pendientes) y `pull()` (trae cambios del servidor) — sin
// reintento en segundo plano (Paso 18, diferido): todo ocurre en primer
// plano mientras la pantalla muestra un indicador de progreso.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../capture/capture_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isSyncing = false;

  Future<void> _sync() async {
    final dependencies = ref.read(appDependenciesProvider);
    setState(() => _isSyncing = true);

    final drainReport = await dependencies.syncEngine.drainOutbox();
    final attachmentReport = await dependencies.attachmentUploadService.drainPending();
    await dependencies.syncEngine.pull();

    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sincronización completa: ${drainReport.applied} visita(s) aplicadas, '
          '${attachmentReport.uploaded} adjunto(s) subido(s).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 12),
            ElevatedButton(
              key: const Key('home_sync_button'),
              onPressed: _isSyncing ? null : _sync,
              child: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sincronizar'),
            ),
          ],
        ),
      ),
    );
  }
}
