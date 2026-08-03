// Tipos del transporte de sync (contrato `server/openapi/v1.yaml`, Pasos
// 1/8/9) + la interfaz `SyncTransport` que el `SyncEngine` consume.
//
// **Alcance deliberado**: el cliente (Paso 10/11) solo modela `Visit` como
// entidad local — `visit_attachment`/`assignment`/`form_template_version`
// no tienen tabla Drift todavía (nota en `data/local/tables.dart`). Por eso
// `PullRow`/bootstrap dejan esas entidades como `Map<String, dynamic>`
// genérico (`entity` + `data` sin tipar) en vez de una unión discriminada
// completa como la del servidor (`sync/schemas.py::EntityRecord`): tipar
// hoy lo que nada en el cliente puede aplicar todavía sería trabajo muerto.
// `SyncEngine.pull()` interpreta la rama `visit`, pasa el resto tal cual.
//
// **No hay implementación real todavía** (Dio/HTTP): el Paso 13 conecta
// `SyncTransport` a `/v1/*` de verdad, con autenticación. Este paso define
// el contrato y lo ejercita con un fake en los tests — "dominio puro... sin
// emulador" (doc 08 §8) significa exactamente esto: el protocolo se puede
// probar entero sin una conexión real.
import 'package:freezed_annotation/freezed_annotation.dart';

import 'result.dart';

part 'sync_transport.freezed.dart';
part 'sync_transport.g.dart';

/// Contrato `RawSyncOp`: una operación del lote de `POST /v1/sync/push`.
@freezed
abstract class RawSyncOp with _$RawSyncOp {
  const factory RawSyncOp({
    required String opUuid,
    required String entity,
    required String opType,
    int? baseVersion,
    required Map<String, dynamic> payload,
  }) = _RawSyncOp;

  factory RawSyncOp.fromJson(Map<String, dynamic> json) => _$RawSyncOpFromJson(json);
}

/// Cuerpo de `POST /v1/sync/push` (contrato `PushRequest`).
@freezed
abstract class PushRequestBody with _$PushRequestBody {
  const factory PushRequestBody({
    required int schemaVersion,
    required String deviceId,
    required String batchUuid,
    required List<RawSyncOp> ops,
  }) = _PushRequestBody;

  factory PushRequestBody.fromJson(Map<String, dynamic> json) => _$PushRequestBodyFromJson(json);
}

/// `OpResultSchema`: el resultado de una operación dentro de `PushResponse`.
/// `status` es texto (`applied`/`conflict`/`rejected`), no un enum Dart, por
/// el mismo motivo que en el servidor (`sync/schemas.py`): el contrato es la
/// fuente de verdad de qué valores son válidos.
@freezed
abstract class PushOpOutcome with _$PushOpOutcome {
  const factory PushOpOutcome({
    required String opUuid,
    required String status,
    Map<String, dynamic>? serverRow,
    int? serverVersion,
    PushOpError? error,
  }) = _PushOpOutcome;

  factory PushOpOutcome.fromJson(Map<String, dynamic> json) => _$PushOpOutcomeFromJson(json);
}

/// `OpErrorSchema`. `message` es el único campo que `SyncEngine` expone al
/// usuario (`OutboxOpState.quarantine.reason`) — nunca `details`, que puede
/// llevar fragmentos del payload que falló (RD-12, mismo principio que en
/// el servidor: el error nunca hace eco del dato sensible).
@freezed
abstract class PushOpError with _$PushOpError {
  const factory PushOpError({required String code, required String message}) = _PushOpError;

  factory PushOpError.fromJson(Map<String, dynamic> json) => _$PushOpErrorFromJson(json);
}

@freezed
abstract class PushResponse with _$PushResponse {
  const factory PushResponse({
    required int schemaVersion,
    required List<PushOpOutcome> results,
  }) = _PushResponse;

  factory PushResponse.fromJson(Map<String, dynamic> json) => _$PushResponseFromJson(json);
}

/// Contrato `EntityRecord` de una fila de `PullResponse.rows` — ver la nota
/// de alcance al inicio del archivo sobre por qué `data` no está tipado.
@freezed
abstract class PullRow with _$PullRow {
  const factory PullRow({required String entity, required Map<String, dynamic> data}) = _PullRow;

  factory PullRow.fromJson(Map<String, dynamic> json) => _$PullRowFromJson(json);
}

/// Contrato `Tombstone`.
@freezed
abstract class PullTombstone with _$PullTombstone {
  const factory PullTombstone({
    required String entity,
    required String id,
    required int changeSeq,
    required DateTime deletedAt,
  }) = _PullTombstone;

  factory PullTombstone.fromJson(Map<String, dynamic> json) => _$PullTombstoneFromJson(json);
}

@freezed
abstract class PullResponse with _$PullResponse {
  const factory PullResponse({
    required List<PullRow> rows,
    required List<PullTombstone> tombstones,
    required String nextCursor,
    required bool hasMore,
  }) = _PullResponse;

  factory PullResponse.fromJson(Map<String, dynamic> json) => _$PullResponseFromJson(json);
}

/// Contrato `BootstrapResponse`, recortado a lo que `SyncEngine` usa hoy
/// (`cursor` + `visits`) — ver la nota de alcance del archivo.
@freezed
abstract class BootstrapResponse with _$BootstrapResponse {
  const factory BootstrapResponse({
    required String cursor,
    required List<Map<String, dynamic>> visits,
  }) = _BootstrapResponse;

  factory BootstrapResponse.fromJson(Map<String, dynamic> json) => _$BootstrapResponseFromJson(json);
}

/// Envuelve cualquier `fromJson` generado (`freezed`/`json_serializable`)
/// para que un payload malformado produzca un `Err` en vez de dejar escapar
/// la excepción que Dart lanza por un campo ausente o de tipo equivocado
/// (RD-02/RD-03, tarea 8 del Paso 12 — "nunca produce una excepción no
/// capturada"). Punto único de esta regla: cualquier transporte real
/// (Paso 13) debe pasar por aquí, no llamar `fromJson` directamente.
Result<T> parseJson<T>(T Function(Map<String, dynamic>) fromJson, Map<String, dynamic> json) {
  try {
    return Result.ok(fromJson(json));
  } on Object catch (e) {
    return Result.err(SyncError.malformedResponse(e.toString()));
  }
}

/// La mitad de red que el `SyncEngine` necesita — implementada por un fake
/// en los tests de este paso y por un cliente Dio real desde el Paso 13.
abstract class SyncTransport {
  Future<Result<PushResponse>> push(PushRequestBody body);
  Future<Result<PullResponse>> pull({required String cursor, int? limit});
  Future<Result<BootstrapResponse>> bootstrap();
}
