// Guardado de una visita capturada (Paso 22, tarea 5) — la lógica, sin UI.
//
// Una visita se guarda **entera y offline** en una sola transacción local
// (`AppDatabase.saveVisitCapture`): la visita, sus adjuntos, las operaciones
// de outbox y la cola de subida. La UI la ve al instante (optimista, doc 08
// §4.2 "FASE OFFLINE"); la red llega después, por el `SyncEngine` y el
// `AttachmentUploadService`.
//
// Reglas que decide este archivo:
//
// - **Solo viajan las respuestas de campos visibles.** El servidor admitiría
//   las de campos ocultos (bien tipadas), pero guardarlas sería guardar lo que
//   el agente dejó de ver; y para foto/firma, subir bytes que nadie pidió.
// - **Solo se guardan los adjuntos referenciados**: los de los campos
//   foto/firma visibles y las fotos adicionales. Una foto repetida antes de
//   guardar sustituye a la anterior, que no llega a crearse.
// - **Orden de las operaciones**: la visita primero y luego sus adjuntos, en
//   el orden de la plantilla; el servidor rechaza un adjunto cuya visita no
//   existe todavía.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';
import '../forms/answers.dart';
import '../forms/form_definition.dart';
import '../location/location_source.dart';

/// Un archivo capturado en esta visita y todavía no guardado.
@immutable
class PendingAttachment {
  const PendingAttachment({
    required this.id,
    required this.sha256,
    required this.localPath,
    required this.mime,
    required this.role,
    required this.capturedAt,
  });

  /// `visit_attachment.id` (UUIDv7, generado en el dispositivo): es lo que se
  /// guarda en `answers` para un campo foto/firma.
  final String id;
  final String sha256;
  final String localPath;
  final String mime;

  /// `foto` | `firma`.
  final String role;
  final DateTime capturedAt;
}

/// Quién captura, desde qué dispositivo y para qué organización.
@immutable
class CaptureIdentity {
  const CaptureIdentity({required this.orgId, required this.userId, required this.deviceId});
  final String orgId;
  final String userId;
  final String deviceId;
}

class VisitCapture {
  VisitCapture({required this.db, String Function()? idGenerator, DateTime Function()? clock})
    : _newId = idGenerator ?? (() => const Uuid().v7()),
      _now = clock ?? DateTime.now;

  final AppDatabase db;
  final String Function() _newId;
  final DateTime Function() _now;

  String newAttachmentId() => _newId();

  /// Guarda la visita. Devuelve su `id`.
  ///
  /// [captured] son los archivos capturados para los campos foto/firma, por
  /// `id`; [extraPhotos], las fotos adicionales fuera de la plantilla.
  Future<String> save({
    required CaptureIdentity identity,
    required String templateVersionId,
    required FormDefinition definition,
    required Map<String, Object?> answers,
    required Map<String, PendingAttachment> captured,
    List<PendingAttachment> extraPhotos = const [],
    LocationFix? fix,
  }) async {
    final visitId = _newId();
    final now = _now().toUtc();

    final kept = keptAnswers(definition, answers);
    final attachments = [
      for (final field in definition.fields)
        if (field is AttachmentRefFieldDef && captured[kept[field.key]] != null) captured[kept[field.key]]!,
      ...extraPhotos,
    ];

    final payload = <String, Object?>{
      'id': visitId,
      'template_version_id': templateVersionId,
      'answers': kept,
      'captured_at': now.toIso8601String(),
      'device_id': identity.deviceId,
      if (fix != null) ...{
        'lat': fix.lat,
        'lon': fix.lon,
        'accuracy_m': fix.accuracyM,
        if (fix.altitudeM != null) 'altitude_m': fix.altitudeM,
      },
    };

    await db.saveVisitCapture(
      visit: VisitsCompanion.insert(
        id: visitId,
        orgId: identity.orgId,
        // `INITIAL_VERSION` del servidor; el valor autoritativo llega tras el push.
        version: 1,
        templateVersionId: templateVersionId,
        answersJson: jsonEncode(kept),
        lat: Value(fix?.lat),
        lon: Value(fix?.lon),
        accuracyM: Value(fix?.accuracyM),
        altitudeM: Value(fix?.altitudeM),
        capturedAt: now,
        deviceId: identity.deviceId,
        createdBy: identity.userId,
      ),
      attachments: [
        for (final (order, a) in attachments.indexed)
          VisitAttachmentsCompanion.insert(
            id: a.id,
            orgId: identity.orgId,
            visitId: visitId,
            sha256: a.sha256,
            role: a.role,
            capturedAt: a.capturedAt.toUtc(),
            position: order,
          ),
      ],
      outboxOps: [
        _op(entity: 'visit', entityId: visitId, payload: payload, now: now),
        for (final (order, a) in attachments.indexed)
          _op(
            entity: 'visit_attachment',
            entityId: a.id,
            payload: {
              'id': a.id,
              'visit_id': visitId,
              'sha256': a.sha256,
              'role': a.role,
              'caption': null,
              'captured_at': a.capturedAt.toUtc().toIso8601String(),
              'order': order,
            },
            now: now,
          ),
      ],
      uploads: [
        for (final a in attachments)
          AttachmentQueueCompanion.insert(
            sha256: a.sha256,
            localPath: a.localPath,
            state: 'pending',
            createdAt: now,
            mime: Value(a.mime),
          ),
      ],
    );
    return visitId;
  }

  OutboxOpsCompanion _op({
    required String entity,
    required String entityId,
    required Map<String, Object?> payload,
    required DateTime now,
  }) => OutboxOpsCompanion.insert(
    opUuid: _newId(),
    entity: entity,
    entityId: entityId,
    opType: 'create',
    baseVersion: const Value(null),
    payloadJson: jsonEncode(payload),
    state: 'pending',
    createdAt: now,
  );
}

/// Las respuestas que se guardan: solo las de campos visibles.
Map<String, Object?> keptAnswers(FormDefinition definition, Map<String, Object?> answers) => {
  for (final field in visibleFields(definition, answers))
    if (answers.containsKey(field.key)) field.key: answers[field.key],
};
