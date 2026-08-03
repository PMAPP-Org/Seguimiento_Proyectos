// `AuthState` — máquina de estados de la sesión del dispositivo (tarea 4 del
// Paso 13, doc 08 ADR-008 "401 ⇒ ... Disconnected"). Sellado como `Result`/
// `SyncError` (Paso 12): el llamador decide con un `switch`/`.when()`, nunca
// comparando un string o un booleano suelto.
import 'package:freezed_annotation/freezed_annotation.dart';

import 'auth_models.dart';

part 'auth_state.freezed.dart';

@freezed
sealed class AuthState with _$AuthState {
  /// Sin sesión: recién instalada la app, o tras `logout()` explícito.
  const factory AuthState.unauthenticated() = Unauthenticated;

  /// Sesión activa. `accessTokenExpiresAt` es informativo (para UI/logs);
  /// la fuente de verdad de si el access token sirve es siempre la
  /// respuesta del servidor, nunca un reloj local sin corregir.
  const factory AuthState.authenticated({
    required UserProfile user,
    required DateTime accessTokenExpiresAt,
  }) = Authenticated;

  /// `401` en un endpoint autenticado y el único refresh permitido también
  /// falló (doc 08 ADR-008: "si el refresh también falla → Disconnected y
  /// re-login, sin borrar la outbox"). Este módulo no toca la outbox porque
  /// no tiene ninguna referencia a ella — la garantía es por construcción,
  /// no por disciplina.
  const factory AuthState.disconnected() = Disconnected;
}
