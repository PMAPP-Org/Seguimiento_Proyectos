// `AuthResult<T>`/`AuthError` — mismo patrón que `core/sync/result.dart`
// (Paso 12, RD-02/RD-03: "prohibido `assert` como validación de datos
// externos", ningún parseo de red produce una excepción no capturada).
// Se duplica en vez de generalizar `Result<T>`/`SyncError` porque ese tipo
// está anclado a `SyncError` (sin parámetro de error), y las variantes de
// error de auth (`invalid_credentials`, `unauthorized`...) no tienen sentido
// en el dominio de sync ni viceversa — igual que `SyncError` no conoce nada
// de HTTP, este archivo no conoce nada de outbox/cursor.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_result.freezed.dart';

@freezed
sealed class AuthResult<T> with _$AuthResult<T> {
  const factory AuthResult.ok(T value) = AuthOk<T>;
  const factory AuthResult.err(AuthError error) = AuthErr<T>;
}

extension AuthResultIsOk<T> on AuthResult<T> {
  bool get isOk => this is AuthOk<T>;
}

/// Todo lo que puede salir mal al hablar con `/v1/auth/*` o
/// `/v1/server/info`, sellado — `AuthController`/`AuthInterceptor` deciden
/// qué hacer mirando el tipo, nunca un string de mensaje.
@freezed
sealed class AuthError with _$AuthError {
  /// Fallo de transporte (sin conexión, timeout, DNS, TLS rechazado...).
  const factory AuthError.network(String message) = AuthNetworkError;

  /// `401` en `POST /v1/auth/login`: credenciales inválidas. Distinto de
  /// `unauthorized` porque login nunca dispara el flujo de refresh (tarea 4:
  /// no tiene sentido "refrescar" una sesión que nunca existió).
  const factory AuthError.invalidCredentials() = InvalidCredentialsAuthError;

  /// `401` en cualquier endpoint autenticado que no sea login — el que sí
  /// dispara el flujo de refresh de la tarea 4.
  const factory AuthError.unauthorized() = UnauthorizedAuthError;

  /// Código HTTP que el protocolo no espera como resultado de negocio.
  const factory AuthError.unexpectedStatus(int statusCode, String body) = AuthUnexpectedStatus;

  /// El cuerpo de la respuesta no tiene la forma que el contrato promete.
  const factory AuthError.malformedResponse(String details) = AuthMalformedResponse;
}

/// Envuelve cualquier `fromJson` generado para que un payload malformado
/// produzca un `AuthResult.err` en vez de dejar escapar la excepción que
/// Dart lanza por un campo ausente o de tipo equivocado — mismo contrato que
/// `parseJson` en `core/sync/sync_transport.dart`.
AuthResult<T> parseAuthJson<T>(T Function(Map<String, dynamic>) fromJson, Map<String, dynamic> json) {
  try {
    return AuthResult.ok(fromJson(json));
  } on Object catch (e) {
    return AuthResult.err(AuthError.malformedResponse(e.toString()));
  }
}
