// Pantalla posterior al login. Botón "Nueva visita" (Tarea 6) + "Sincronizar"
// (Tarea 7 del plan de despliegue del demo): dispara, en orden,
// `drainOutbox()` (push del outbox de visitas), `drainPending()` (subida de
// adjuntos pendientes) y `pull()` (trae cambios del servidor) — sin
// reintento en segundo plano (Paso 18, diferido): todo ocurre en primer
// plano mientras la pantalla muestra un indicador de progreso.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/sync/result.dart';
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

    try {
      final drainReport = await dependencies.syncEngine.drainOutbox();
      final attachmentReport = await dependencies.attachmentUploadService.drainPending();
      final pullResult = await dependencies.syncEngine.pull();

      if (!mounted) return;

      // Hallazgo Crítico/Importante de la revisión final: antes de este fix
      // el SnackBar siempre decía "completa" pase lo que pase -- descartaba
      // `quarantined`/`deferred` de `drainReport`, `failed` de
      // `attachmentReport` y el `Result` de `pull()`. Un operador del demo no
      // tenía forma de distinguir "todo sincronizó" de "el servidor rechazó
      // la visita" o "no se pudo subir la foto" con solo mirar la pantalla.
      final hasIssues =
          drainReport.quarantined > 0 ||
          drainReport.deferred > 0 ||
          attachmentReport.failed > 0 ||
          !pullResult.isOk;

      final message = hasIssues
          ? 'Sincronización incompleta: ${drainReport.applied} visita(s) aplicadas, '
                '${drainReport.quarantined} rechazada(s), ${drainReport.deferred} pendiente(s) de '
                'reintento, ${attachmentReport.uploaded} adjunto(s) subido(s), '
                '${attachmentReport.failed} adjunto(s) fallido(s)'
                '${pullResult.isOk ? '' : ', no se pudieron traer los cambios del servidor'}.'
          : 'Sincronización completa: ${drainReport.applied} visita(s) aplicadas, '
                '${attachmentReport.uploaded} adjunto(s) subido(s).';

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      // Defensa en profundidad: pase lo que pase arriba, el botón nunca debe
      // quedar deshabilitado permanentemente (hallazgo de revisión Tarea 7).
      if (mounted) setState(() => _isSyncing = false);
    }
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
