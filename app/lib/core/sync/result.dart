// `Result<T>` — Paso 12, tarea 8 (RD-02/RD-03 en cliente): "prohibido
// `assert` como validación de datos externos". Todo parseo de una respuesta
// del servidor devuelve `Ok`/`Err` explícito en vez de lanzar o de confiar
// en que el campo esperado esté ahí — un payload malformado nunca produce
// una excepción no capturada ni un crash, produce un `Err` tipado que el
// llamador está obligado a manejar (Dart no tiene checked exceptions; un
// tipo de retorno sellado es el único mecanismo real de "obligado").
import 'package:freezed_annotation/freezed_annotation.dart';

part 'result.freezed.dart';

// `freezed` ya genera `.when(ok: ..., err: ...)` para esta unión sellada
// (una extensión `ResultPatterns<T>` a partir de los nombres de los factory
// constructors) — no se escribe una segunda extensión con el mismo método:
// dos extensiones con un miembro del mismo nombre sobre el mismo tipo son
// ambiguas para el analizador y ninguna llamada a `.when()` compilaría.
@freezed
sealed class Result<T> with _$Result<T> {
  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(SyncError error) = Err<T>;
}

/// Atajo para el caso común "solo me importa si fue bien" — no choca con el
/// `.when()` generado porque `freezed` no genera `isOk`.
extension ResultIsOk<T> on Result<T> {
  bool get isOk => this is Ok<T>;
}

/// Todo lo que puede salir mal al hablar con `/v1/sync/*` o `/v1/auth/*`,
/// sellado — el `SyncEngine` decide qué hacer con cada variante (reintentar
/// con backoff, disparar un bootstrap, etc.) mirando el tipo, nunca un
/// string de mensaje de error.
@freezed
sealed class SyncError with _$SyncError {
  /// Fallo de transporte (sin conexión, timeout, DNS...). Reintentable con
  /// backoff — el `SyncEngine` no distingue el motivo exacto, todos vuelven
  /// la operación a `pending`.
  const factory SyncError.network(String message) = NetworkError;

  /// Respuesta HTTP recibida pero con un código que el protocolo no espera
  /// como "resultado de negocio" (5xx del servidor, por ejemplo). El cuerpo
  /// se conserva para diagnóstico, nunca se interpreta como datos válidos.
  const factory SyncError.unexpectedStatus(int statusCode, String body) = UnexpectedStatus;

  /// `409 cursor_expired` (contrato `sync/pull`) — el único error que el
  /// `SyncEngine` traduce a una acción concreta y automática: bootstrap
  /// completo (tarea 7 del Paso 12), no un reintento con backoff.
  const factory SyncError.cursorExpired() = CursorExpiredError;

  /// El cuerpo de la respuesta no tiene la forma que el contrato promete
  /// (campo ausente, tipo equivocado, JSON inválido). Nunca se llega aquí
  /// vía una excepción no capturada — el parseo la produce explícitamente.
  const factory SyncError.malformedResponse(String details) = MalformedResponse;
}
