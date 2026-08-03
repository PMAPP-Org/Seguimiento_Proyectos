// `SyncEngine` — Paso 12: dominio puro del protocolo de sync (outbox, CAS,
// cursor), contraparte cliente de `server/visitacampo/sync/{services,pull}.py`
// (Pasos 8/9). "Puro" no significa "sin base de datos": significa sin IO de
// red real (`SyncTransport` es una interfaz, un fake en los tests) — el
// `AppDatabase` (Paso 11) sí es real incluso en test, porque `NativeDatabase`
// funciona en el host sin emulador (ya verificado en el Paso 11).
//
// **Alcance de entidades**: solo `visit` — es la única entidad que el push
// del servidor acepta escribir en el MVP (Paso 8) y la única con tabla local
// (Paso 11). El pull puede traer otras entidades; se ignoran a propósito
// hasta que tengan tabla (ver `sync_transport.dart`).
//
// **Backoff no persistido**: `attempt`/`nextAttemptAt` viven en memoria del
// `SyncEngine` (`_backoffState`), no en `OutboxOps` — se reinician si la app
// se reinicia a mitad de una racha de fallos. Aceptable en Fase 0 (S-01:
// <20 dispositivos concurrentes en el MVP, el riesgo de "thundering herd"
// es bajo); revisar si el volumen de Fase 2 lo justifica.
import 'dart:convert';

// `JsonKey` existe en ambos paquetes (`drift` lo usa para otra cosa);
// `freezed_annotation` es el que este archivo necesita para `@freezed`.
import 'package:drift/drift.dart' hide JsonKey;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';
import 'backoff.dart';
import 'result.dart';
import 'sync_transport.dart';

part 'sync_engine.freezed.dart';

/// Cursor de un dispositivo que nunca sincronizó nada (`sync/cursor.py` del
/// servidor: `CURSOR_ZERO`, `change_seq=0` codificado).
const cursorZero = 'c1:00000000000000000000';

@freezed
abstract class DrainReport with _$DrainReport {
  const factory DrainReport({
    required int sent,
    required int applied,
    required int conflicted,
    required int quarantined,
    required int deferred,
  }) = _DrainReport;

  static const empty = DrainReport(sent: 0, applied: 0, conflicted: 0, quarantined: 0, deferred: 0);
}

class _Backoff {
  const _Backoff(this.attempt, this.nextAttemptAt);
  final int attempt;
  final DateTime nextAttemptAt;
}

class SyncEngine {
  SyncEngine({
    required this.db,
    required this.transport,
    required this.deviceId,
    String Function()? idGenerator,
    DateTime Function()? clock,
    this.backoff = const ExponentialBackoffWithJitter(),
    this.maxBatchOps = 500,
  }) : _generateId = idGenerator ?? (() => const Uuid().v7()),
       _now = clock ?? DateTime.now;

  final AppDatabase db;
  final SyncTransport transport;
  final String deviceId;
  final BackoffPolicy backoff;
  final int maxBatchOps;
  final String Function() _generateId;
  final DateTime Function() _now;

  final Map<String, _Backoff> _backoffState = {};

  static const _statePending = 'pending';
  static const _stateInflight = 'inflight';
  static const _stateQuarantine = 'quarantine';

  /// Encola una operación de `visit` (tarea 2: `op_uuid` UUIDv7 generado en
  /// el dispositivo). Si `visit` no es `null`, la guarda atómicamente junto
  /// con la fila local (`AppDatabase.saveVisitWithOutboxOp`, Paso 11) —
  /// "guardar visita + encolar operación" en una sola transacción.
  Future<String> enqueueVisitOp({
    required String entityId,
    required String opType,
    int? baseVersion,
    required Map<String, dynamic> payload,
    VisitsCompanion? visit,
  }) async {
    final opUuid = _generateId();
    final outboxOp = OutboxOpsCompanion.insert(
      opUuid: opUuid,
      entity: 'visit',
      entityId: entityId,
      opType: opType,
      baseVersion: Value(baseVersion),
      payloadJson: jsonEncode(payload),
      state: _statePending,
      createdAt: _now(),
    );
    if (visit != null) {
      await db.saveVisitWithOutboxOp(visit: visit, outboxOp: outboxOp);
    } else {
      await db.into(db.outboxOps).insert(outboxOp);
    }
    return opUuid;
  }

  /// Tarea 3: toma un lote del outbox (FIFO, hasta `maxBatchOps` — el límite
  /// de 500 del contrato, Paso 1/8) y lo drena contra `POST /v1/sync/push`.
  /// No hace nada si no hay operaciones **debidas** (`pending` sin backoff
  /// pendiente) — llamar a `drainOutbox()` a menudo es seguro y barato.
  Future<DrainReport> drainOutbox() async {
    final now = _now();
    final pendingRows =
        await (db.select(db.outboxOps)
              ..where((t) => t.state.equals(_statePending))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();

    final due = pendingRows.where((row) {
      final b = _backoffState[row.opUuid];
      return b == null || !b.nextAttemptAt.isAfter(now);
    }).toList();

    if (due.isEmpty) return DrainReport.empty;

    final batch = due.length <= maxBatchOps ? due : due.sublist(0, maxBatchOps);

    await db.batch((b) {
      for (final row in batch) {
        b.update(
          db.outboxOps,
          const OutboxOpsCompanion(state: Value(_stateInflight)),
          where: (t) => t.opUuid.equals(row.opUuid),
        );
      }
    });

    final body = PushRequestBody(
      schemaVersion: 1,
      deviceId: deviceId,
      batchUuid: _generateId(),
      ops: batch.map(_toRawSyncOp).toList(),
    );

    final result = await transport.push(body);
    return result.when(
      ok: (response) => _applyPushResponse(batch, response),
      err: (error) => _handleTransportFailure(batch),
    );
  }

  RawSyncOp _toRawSyncOp(OutboxOp row) => RawSyncOp(
    opUuid: row.opUuid,
    entity: row.entity,
    opType: row.opType,
    baseVersion: row.baseVersion,
    payload: jsonDecode(row.payloadJson) as Map<String, dynamic>,
  );

  Future<DrainReport> _applyPushResponse(List<OutboxOp> batch, PushResponse response) async {
    var applied = 0;
    var conflicted = 0;
    var quarantined = 0;
    final byUuid = {for (final r in response.results) r.opUuid: r};

    await db.transaction(() async {
      for (final row in batch) {
        final outcome = byUuid[row.opUuid];
        if (outcome == null) {
          // El servidor no devolvió resultado para esta op: se trata como
          // fallo de transporte (se reintenta) — nunca se asume éxito sin
          // confirmación explícita (RD-02/RD-03: no interpretar la ausencia
          // de dato como un valor).
          await _requeueWithBackoff(row);
          continue;
        }

        // `applied`/`conflict` son terminales para esta op: `conflicted →
        // [*]` del diagrama (doc 08 §4.3) — la fila local se reemplaza por
        // `server_row` y el OutboxOp se borra, sin "merge de 3 vías"
        // (ADR-003, decisión explícita).
        if (outcome.status == 'applied' || outcome.status == 'conflict') {
          if (outcome.serverRow != null) {
            await _upsertVisitFromServerRow(outcome.serverRow!);
          }
          await (db.delete(db.outboxOps)..where((t) => t.opUuid.equals(row.opUuid))).go();
          if (outcome.status == 'applied') {
            applied++;
          } else {
            conflicted++;
          }
        } else if (outcome.status == 'rejected') {
          // `rejected → quarantine` inmediato (tarea 5): nunca se descarta
          // en silencio.
          final reason = outcome.error?.message ?? 'El servidor rechazó la operación.';
          await (db.update(db.outboxOps)..where(
                (t) => t.opUuid.equals(row.opUuid),
              ))
              .write(
                OutboxOpsCompanion(
                  state: const Value(_stateQuarantine),
                  errorMessage: Value(reason),
                ),
              );
          quarantined++;
        } else {
          // Estado que el contrato no documenta: tampoco se descarta en
          // silencio, va a quarantine con el estado crudo como motivo.
          await (db.update(db.outboxOps)..where(
                (t) => t.opUuid.equals(row.opUuid),
              ))
              .write(
                OutboxOpsCompanion(
                  state: const Value(_stateQuarantine),
                  errorMessage: Value('Estado de servidor no reconocido: ${outcome.status}'),
                ),
              );
          quarantined++;
        }
      }
    });

    for (final row in batch) {
      _backoffState.remove(row.opUuid);
    }
    return DrainReport(
      sent: batch.length,
      applied: applied,
      conflicted: conflicted,
      quarantined: quarantined,
      deferred: batch.length - applied - conflicted - quarantined,
    );
  }

  Future<DrainReport> _handleTransportFailure(List<OutboxOp> batch) async {
    for (final row in batch) {
      await _requeueWithBackoff(row);
    }
    return DrainReport(sent: 0, applied: 0, conflicted: 0, quarantined: 0, deferred: batch.length);
  }

  /// `inflight → pending` con backoff (tarea 1). Ver el docstring del
  /// archivo sobre por qué `attempt`/`nextAttemptAt` no se persisten.
  Future<void> _requeueWithBackoff(OutboxOp row) async {
    final previousAttempt = _backoffState[row.opUuid]?.attempt ?? 0;
    final delay = backoff.delayFor(previousAttempt);
    _backoffState[row.opUuid] = _Backoff(previousAttempt + 1, _now().add(delay));
    await (db.update(db.outboxOps)..where(
          (t) => t.opUuid.equals(row.opUuid),
        ))
        .write(const OutboxOpsCompanion(state: Value(_statePending)));
  }

  /// `server_row` (`VisitRecord.data`, contrato Paso 8/9) tiene las mismas
  /// claves en snake_case que `VisitsCompanion` — la traducción vive aquí
  /// porque solo el push/pull de `visit` la necesita.
  Future<void> _upsertVisitFromServerRow(Map<String, dynamic> serverRow) async {
    final companion = VisitsCompanion.insert(
      id: serverRow['id'] as String,
      orgId: serverRow['org_id'] as String,
      version: serverRow['version'] as int,
      changeSeq: Value(serverRow['change_seq'] as int?),
      deletedAt: Value(_parseNullableDate(serverRow['deleted_at'])),
      templateVersionId: serverRow['template_version_id'] as String,
      answersJson: jsonEncode(serverRow['answers']),
      lat: Value(serverRow['lat'] as double?),
      lon: Value(serverRow['lon'] as double?),
      accuracyM: Value(serverRow['accuracy_m'] as double?),
      altitudeM: Value(serverRow['altitude_m'] as double?),
      capturedAt: DateTime.parse(serverRow['captured_at'] as String),
      deviceId: serverRow['device_id'] as String,
      createdBy: serverRow['created_by'] as String,
    );
    await db.into(db.visits).insertOnConflictUpdate(companion);
  }

  DateTime? _parseNullableDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  /// Tarea 6: pull incremental desde el cursor persistido, filas y
  /// tombstones aplicados en una transacción local, `next_cursor` guardado.
  /// Tarea 7: `409 cursor_expired` dispara un bootstrap automático — nunca
  /// se propaga como error al llamador, es la recuperación, no un fallo.
  Future<Result<bool>> pull({int? limit}) async {
    final cursor = await db.readCursor() ?? cursorZero;
    final result = await transport.pull(cursor: cursor, limit: limit);
    return result.when(
      ok: (response) => _applyPullResponse(response),
      err: (error) => switch (error) {
        CursorExpiredError() => _bootstrapAfterCursorExpired(),
        _ => Future.value(Result<bool>.err(error)),
      },
    );
  }

  Future<Result<bool>> _applyPullResponse(PullResponse response) async {
    await db.transaction(() async {
      for (final row in response.rows) {
        if (row.entity == 'visit') {
          await _upsertVisitFromServerRow(row.data);
        }
        // Otras entidades: sin tabla local todavía (ver docstring del
        // archivo) — se ignoran a propósito hasta el Paso 21+.
      }
      for (final tombstone in response.tombstones) {
        if (tombstone.entity == 'visit') {
          await (db.delete(db.visits)..where((t) => t.id.equals(tombstone.id))).go();
        }
      }
      await db.writeCursor(response.nextCursor, now: _now());
    });
    return const Result.ok(true);
  }

  Future<Result<bool>> _bootstrapAfterCursorExpired() async {
    final result = await transport.bootstrap();
    return result.when(
      ok: (bootstrap) async {
        await db.transaction(() async {
          for (final visitJson in bootstrap.visits) {
            await _upsertVisitFromServerRow(visitJson);
          }
          await db.writeCursor(bootstrap.cursor, now: _now());
        });
        return const Result.ok(true);
      },
      err: (error) async => Result<bool>.err(error),
    );
  }

  /// `quarantine → pending`: reintento explícito del usuario (Paso 23).
  Future<void> retryQuarantined(String opUuid) {
    return (db.update(db.outboxOps)..where((t) => t.opUuid.equals(opUuid))).write(
      const OutboxOpsCompanion(state: Value(_statePending), errorMessage: Value(null)),
    );
  }

  /// `quarantine → [*]`: descarte explícito del usuario (Paso 23). Borra el
  /// `OutboxOp`; la fila de negocio local (`visits`) no se toca — descartar
  /// el intento de sincronizar no borra el trabajo del usuario, solo deja de
  /// intentar enviarlo.
  Future<void> discardQuarantined(String opUuid) {
    return (db.delete(db.outboxOps)..where((t) => t.opUuid.equals(opUuid))).go();
  }
}
