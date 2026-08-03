// Modelos del contrato `/v1/auth/*` y `/v1/server/info`
// (`server/openapi/v1.yaml`, Paso 1; implementación real: Paso 7 y
// `serverinfo/schemas.py`). `field_rename: snake` (`app/build.yaml`, hallazgo
// del Paso 12) traduce el camelCase de estos campos al snake_case real del
// wire sin anotar cada uno.
//
// `platform` se deja como `String` (no un enum Dart) por el mismo motivo que
// `PushOpOutcome.status` en `sync_transport.dart`: el contrato es la fuente
// de verdad de qué valores son válidos, no una copia que se puede desincronizar.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_models.freezed.dart';
part 'auth_models.g.dart';

/// Contrato `DeviceInfo`.
@freezed
abstract class DeviceInfo with _$DeviceInfo {
  const factory DeviceInfo({
    required String deviceId,
    required String platform,
    String? osVersion,
    String? model,
    required String appVersion,
    String? displayName,
  }) = _DeviceInfo;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => _$DeviceInfoFromJson(json);
}

/// Cuerpo de `POST /v1/auth/login` (contrato `LoginRequest`).
@freezed
abstract class LoginRequest with _$LoginRequest {
  const factory LoginRequest({
    required String username,
    required String password,
    required DeviceInfo deviceInfo,
  }) = _LoginRequest;

  factory LoginRequest.fromJson(Map<String, dynamic> json) => _$LoginRequestFromJson(json);
}

/// Contrato `TokenPair` — emitido en login y en cada rotación de refresh.
@freezed
abstract class TokenPair with _$TokenPair {
  const factory TokenPair({
    required String accessToken,
    required String tokenType,
    required int expiresIn,
    required String refreshToken,
    required int refreshExpiresIn,
    required DateTime serverTime,
  }) = _TokenPair;

  factory TokenPair.fromJson(Map<String, dynamic> json) => _$TokenPairFromJson(json);
}

/// Contrato `UserProfile`.
@freezed
abstract class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String id,
    required String username,
    String? displayName,
    required String orgId,
    required List<String> roles,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) => _$UserProfileFromJson(json);
}

/// Cuerpo de `200 OK` de `POST /v1/auth/login` (contrato `LoginResponse`).
@freezed
abstract class LoginResponse with _$LoginResponse {
  const factory LoginResponse({required TokenPair tokens, required UserProfile user}) = _LoginResponse;

  factory LoginResponse.fromJson(Map<String, dynamic> json) => _$LoginResponseFromJson(json);
}

/// Cuerpo de `POST /v1/auth/refresh` (contrato `RefreshRequest`).
@freezed
abstract class RefreshRequest with _$RefreshRequest {
  const factory RefreshRequest({required String refreshToken, required String deviceId}) = _RefreshRequest;

  factory RefreshRequest.fromJson(Map<String, dynamic> json) => _$RefreshRequestFromJson(json);
}

/// Cuerpo de `POST /v1/auth/logout` (contrato `LogoutRequest`).
@freezed
abstract class LogoutRequest with _$LogoutRequest {
  const factory LogoutRequest({required String refreshToken}) = _LogoutRequest;

  factory LogoutRequest.fromJson(Map<String, dynamic> json) => _$LogoutRequestFromJson(json);
}

/// Contrato `ServerCapabilities` (límites operativos que el cliente debe
/// respetar — se leen del servidor, no se codifican en la app).
@freezed
abstract class ServerCapabilities with _$ServerCapabilities {
  const factory ServerCapabilities({
    required int syncPushMaxOps,
    required int syncPushMaxBytes,
    required int syncPullMaxLimit,
    required int attachmentMaxBytes,
    required List<String> attachmentAllowedMime,
  }) = _ServerCapabilities;

  factory ServerCapabilities.fromJson(Map<String, dynamic> json) =>
      _$ServerCapabilitiesFromJson(json);
}

/// Cuerpo de `GET /v1/server/info` (contrato `ServerInfo`) — negociación de
/// compatibilidad (tarea 5 del Paso 13): `schema_version` y `server_time`.
@freezed
abstract class ServerInfo with _$ServerInfo {
  const factory ServerInfo({
    required String apiVersion,
    required int schemaVersion,
    required int minSupportedSchemaVersion,
    required DateTime serverTime,
    required ServerCapabilities capabilities,
  }) = _ServerInfo;

  factory ServerInfo.fromJson(Map<String, dynamic> json) => _$ServerInfoFromJson(json);
}
