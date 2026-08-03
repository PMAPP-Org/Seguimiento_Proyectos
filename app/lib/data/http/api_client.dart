// `AuthApiClient` — implementación Dio real de `AuthTransport` (tarea 1 del
// Paso 13): consume `/v1/auth/login`, `/v1/auth/refresh`, `/v1/auth/logout`,
// `/v1/server/info`.
//
// **Sobre RD-01/ADR-009 (tarea 2 del Paso 13, ver `lint_no_tls_bypass.sh`)**:
// este archivo **deliberadamente no toca** el hook de aceptación de
// certificados inválidos de `HttpClientAdapter`, ni ningún otro parámetro de
// validación de certificado (nombre del identificador omitido a propósito
// en todo este archivo: el lint de Paso 3 prohíbe que aparezca en cualquier
// archivo fuera de `core/security/trust_store/`, que no existe hasta el
// Paso 16 — no "prohíbe que retorne `true`", prohíbe que **aparezca**). La
// política mínima de este paso ("nunca aceptar certificados inválidos") ya
// es el comportamiento por defecto de `HttpClientAdapter`/`SecurityContext`
// de Dart: sin override, un servidor con certificado inválido o no confiable
// por la cadena de CA hace fallar el handshake TLS y la request termina en
// un `DioException` (`DioExceptionType.connectionError`), nunca en una
// respuesta. Verificado en `test/core/auth/tls_default_rejects_invalid_cert_test.dart`
// contra un servidor HTTPS real con certificado autofirmado. El Paso 16
// introduce `TrustStore` como la única excepción auditada a este default,
// para pinning de SPKI y TOFU explícito.
import 'package:dio/dio.dart';

import '../../core/auth/auth_models.dart';
import '../../core/auth/auth_result.dart';
import '../../core/auth/auth_transport.dart';

class AuthApiClient implements AuthTransport {
  const AuthApiClient(this._dio);

  final Dio _dio;

  @override
  Future<AuthResult<LoginResponse>> login({
    required String username,
    required String password,
    required DeviceInfo deviceInfo,
  }) {
    final body = LoginRequest(username: username, password: password, deviceInfo: deviceInfo).toJson();
    return _post('/v1/auth/login', body, LoginResponse.fromJson, isLogin: true);
  }

  @override
  Future<AuthResult<TokenPair>> refresh({required String refreshToken, required String deviceId}) {
    final body = RefreshRequest(refreshToken: refreshToken, deviceId: deviceId).toJson();
    return _post('/v1/auth/refresh', body, TokenPair.fromJson);
  }

  @override
  Future<AuthResult<void>> logout({required String accessToken, required String refreshToken}) async {
    try {
      await _dio.post<void>(
        '/v1/auth/logout',
        data: LogoutRequest(refreshToken: refreshToken).toJson(),
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return const AuthResult.ok(null);
    } on DioException catch (e) {
      return AuthResult.err(_mapError(e));
    }
  }

  @override
  Future<AuthResult<ServerInfo>> serverInfo({required String accessToken}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/server/info',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return parseAuthJson(ServerInfo.fromJson, response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      return AuthResult.err(_mapError(e));
    }
  }

  Future<AuthResult<T>> _post<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson, {
    bool isLogin = false,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body);
      return parseAuthJson(fromJson, response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      return AuthResult.err(_mapError(e, isLogin: isLogin));
    }
  }

  /// Traduce un `DioException` a `AuthError` (contrato de error uniforme del
  /// servidor, `core/api_errors.py`): `status == null` es fallo de
  /// transporte (sin respuesta del servidor, incluido el TLS rechazado del
  /// docstring de arriba); cualquier otro código se refleja tal cual.
  AuthError _mapError(DioException e, {bool isLogin = false}) {
    final status = e.response?.statusCode;
    if (status == null) {
      return AuthError.network(e.message ?? e.type.name);
    }
    if (status == 401) {
      // `authn/services.py::InvalidCredentials.code == "invalid_credentials"`
      // solo puede salir de `/auth/login`; cualquier otro 401 es la sesión
      // vigente que dejó de serlo (`core/api_errors.py::CODE_BY_STATUS[401]
      // == "unauthenticated"`).
      return isLogin ? const AuthError.invalidCredentials() : const AuthError.unauthorized();
    }
    final body = e.response?.data;
    return AuthError.unexpectedStatus(status, body == null ? '' : body.toString());
  }
}
