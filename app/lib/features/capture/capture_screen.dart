// Pantalla de captura — Tarea 6 del plan de despliegue del demo. Formulario
// FIJO (altura_cm + notas, no el renderer dinámico de JSON Schema del Paso
// 21, diferido), GPS y una foto, persistidos en una sola transacción local
// vía `SyncEngine.enqueueVisitOp` (Paso 12) + `AttachmentQueueRepository`
// (Step 6 de esta tarea). No sincroniza nada por red — eso es la Tarea 7.
//
// `template_version_id` se pega a mano (Decisión de diseño 7 del plan): el
// renderer dinámico y el flujo de asignación de plantillas están fuera de
// alcance; el operador del demo siembra una `FormTemplateVersion` vía Django
// Admin antes de la prueba y pega aquí su UUID.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/auth_state.dart';
import '../../core/capture/photo_capture.dart';
import '../../core/location/location_source.dart';
import '../../core/providers.dart';
import '../../data/local/attachment_queue_repository.dart';
import '../../data/local/database.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _templateController = TextEditingController();
  final _alturaController = TextEditingController();
  final _notasController = TextEditingController();

  LocationFix? _fix;
  CapturedPhoto? _photo;
  bool _isSaving = false;

  @override
  void dispose() {
    _templateController.dispose();
    _alturaController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    final dependencies = ref.read(appDependenciesProvider);
    final fix = await dependencies.locationSource.getCurrentFix();
    if (!mounted) return;
    setState(() => _fix = fix);
  }

  Future<void> _takePhoto() async {
    final dependencies = ref.read(appDependenciesProvider);
    final photo = await dependencies.photoCapture.takePhoto();
    if (!mounted) return;
    setState(() => _photo = photo);
  }

  Future<void> _save() async {
    final dependencies = ref.read(appDependenciesProvider);
    final authState = dependencies.authController.state;
    if (authState is! Authenticated) return;

    setState(() => _isSaving = true);

    final visitId = const Uuid().v7();
    final now = DateTime.now().toUtc();
    final capturedAt = now.toIso8601String();
    final answers = <String, dynamic>{
      'altura_cm': int.tryParse(_alturaController.text) ?? 0,
      'notas': _notasController.text,
    };

    final payload = <String, dynamic>{
      'id': visitId,
      'template_version_id': _templateController.text,
      'answers': answers,
      'captured_at': capturedAt,
      'device_id': dependencies.deviceId,
      if (_fix != null) 'lat': _fix!.lat,
      if (_fix != null) 'lon': _fix!.lon,
      if (_fix != null) 'accuracy_m': _fix!.accuracyM,
      if (_fix != null && _fix!.altitudeM != null) 'altitude_m': _fix!.altitudeM,
    };

    final visitCompanion = VisitsCompanion.insert(
      id: visitId,
      orgId: authState.user.orgId,
      // `INITIAL_VERSION` del servidor (`core/models/base.py`) es 1: el
      // cliente crea la fila local con la misma convención, aunque el
      // servidor es quien fija el valor autoritativo tras el push.
      version: 1,
      changeSeq: const Value(null),
      deletedAt: const Value(null),
      templateVersionId: _templateController.text,
      answersJson: jsonEncode(answers),
      lat: Value(_fix?.lat),
      lon: Value(_fix?.lon),
      accuracyM: Value(_fix?.accuracyM),
      altitudeM: Value(_fix?.altitudeM),
      capturedAt: now,
      deviceId: dependencies.deviceId,
      createdBy: authState.user.id,
    );

    // `SyncEngine` no forma parte de `AppDependencies` todavía (lo añade la
    // Tarea 7) — esta tarea solo necesita `AppDatabase.saveVisitWithOutboxOp`
    // directamente, con la misma forma de `OutboxOpsCompanion` que
    // `SyncEngine.enqueueVisitOp` construye (`core/sync/sync_engine.dart`).
    await dependencies.database.saveVisitWithOutboxOp(
      visit: visitCompanion,
      outboxOp: OutboxOpsCompanion.insert(
        opUuid: const Uuid().v7(),
        entity: 'visit',
        entityId: visitId,
        opType: 'create',
        baseVersion: const Value(null),
        payloadJson: jsonEncode(payload),
        state: 'pending',
        createdAt: now,
      ),
    );

    final photo = _photo;
    if (photo != null) {
      await AttachmentQueueRepository(
        dependencies.database,
      ).enqueue(sha256: photo.sha256, localPath: photo.file.path, now: now);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visita guardada.')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva visita')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('capture_template_field'),
              controller: _templateController,
              decoration: const InputDecoration(labelText: 'ID de plantilla (UUID)'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('capture_altura_field'),
              controller: _alturaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Altura (cm)'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('capture_notas_field'),
              controller: _notasController,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const Key('capture_get_location_button'),
              onPressed: _getLocation,
              child: const Text('Obtener ubicación'),
            ),
            if (_fix != null) Text('lat: ${_fix!.lat}, lon: ${_fix!.lon}'),
            const SizedBox(height: 12),
            ElevatedButton(
              key: const Key('capture_take_photo_button'),
              onPressed: _takePhoto,
              child: const Text('Tomar foto'),
            ),
            if (_photo != null) Text('Foto: ${_photo!.file.path.split('/').last}'),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const Key('capture_save_button'),
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar visita'),
            ),
          ],
        ),
      ),
    );
  }
}
