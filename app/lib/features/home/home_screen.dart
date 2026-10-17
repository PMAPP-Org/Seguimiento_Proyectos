// Pantalla posterior al login. Botón "Nueva visita" (Tarea 6) + "Sincronizar"
// (Tarea 7 del plan de despliegue del demo): dispara, en orden,
// `drainOutbox()` (push del outbox de visitas), `drainPending()` (subida de
// adjuntos pendientes) y `pull()` (trae cambios del servidor) — sin
// reintento en segundo plano (Paso 18, diferido): todo ocurre en primer
// plano mientras la pantalla muestra un indicador de progreso.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_state.dart';
import '../../core/providers.dart';
import '../../core/sync/result.dart';
import '../../data/local/visit_status_repository.dart';
import '../../l10n/l10n.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/app_page_body.dart';
import '../capture/capture_screen.dart';
import 'visit_status_list.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isSyncing = false;

  /// Visitas recientes con su estado (Paso 22). `null` mientras se cargan.
  List<VisitSummary>? _visits;

  @override
  void initState() {
    super.initState();
    _loadVisits();
  }

  Future<void> _loadVisits() async {
    final dependencies = ref.read(appDependenciesProvider);
    final authState = dependencies.authController.state;
    final visits = authState is Authenticated
        ? await dependencies.visitStatus.recentVisits(orgId: authState.user.orgId)
        : const <VisitSummary>[];
    if (mounted) setState(() => _visits = visits);
  }

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

      final l10n = context.l10n;
      final message = hasIssues
          ? [
              l10n.syncIncomplete(
                drainReport.applied,
                drainReport.quarantined,
                drainReport.deferred,
                attachmentReport.uploaded,
                attachmentReport.failed,
              ),
              if (!pullResult.isOk) l10n.syncPullFailed,
            ].join(' ')
          : l10n.syncComplete(drainReport.applied, attachmentReport.uploaded);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      // Defensa en profundidad: pase lo que pase arriba, el botón nunca debe
      // quedar deshabilitado permanentemente (hallazgo de revisión Tarea 7).
      if (mounted) setState(() => _isSyncing = false);
      await _loadVisits();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = ref.watch(appDependenciesProvider);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: AppPageBody(
        children: [
          Text(l10n.homeSessionStarted(dependencies.deviceId), textAlign: TextAlign.center),
          const AppGap.lg(),
          AppButton(
            key: const Key('home_new_visit_button'),
            label: l10n.homeNewVisit,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CaptureScreen()),
              );
              // UI optimista: la visita recién guardada aparece ya, sin red.
              await _loadVisits();
            },
          ),
          const AppGap.sm(),
          AppButton(
            key: const Key('home_sync_button'),
            label: l10n.homeSync,
            loadingLabel: l10n.homeSyncing,
            isLoading: _isSyncing,
            onPressed: _sync,
          ),
          const AppGap.lg(),
          Text(l10n.homeRecentVisits, style: Theme.of(context).textTheme.titleMedium),
          if (_visits == null)
            const Center(child: CircularProgressIndicator())
          else
            VisitStatusList(visits: _visits!),
        ],
      ),
    );
  }
}
