// Tests de `AuthApiClient` (Paso 13, tarea 1) — mapeo JSON del contrato
// (`server/openapi/v1.yaml`) y de errores Dio a `AuthError`, contra un
// `HttpClientAdapter` falso (sin red real, ver `fake_http_client_adapter.dart`).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/auth/auth_models.dart';
import 'package:visitacampo/core/auth/auth_result.dart';
import 'package:visitacampo/data/http/api_client.dart';

import 'fake_http_client_adapter.dart';

const _deviceInfo = DeviceInfo(deviceId: 'device-1', platform: 'android', appVersion: '1.0.0');

({Dio dio, AuthApiClient client, FakeHttpClientAdapter adapter}) _clientWith(FakeHttpHandler handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://visitacampo.test'));
  final adapter = FakeHttpClientAdapter(handler);
  dio.httpClientAdapter = adapter;
  return (dio: dio, client: AuthApiClient(dio), adapter: adapter);
}

void main() {
  group('AuthApiClient.login', () {
    test('200 -> parsea LoginResponse y envía el cuerpo del contrato', () async {
      final ctx = _clientWith((options) {
        // `options.data` es el `Map` original pasado a `dio.post(data: ...)`
        // sin serializar todavía — la codificación a bytes ocurre en
        // `requestStream`, que este fake ignora (Dio.fetch la produce, pero
        // el adapter no está obligado a consumirla para responder).
        final body = options.data as Map<String, dynamic>;
        expect(body['username'], 'agente1');
        final deviceInfoJson = body['device_info'] as Map<String, dynamic>;
        expect(deviceInfoJson['device_id'], 'device-1');
        return jsonResponseBody({
          'tokens': {
            'access_token': 'access-1',
            'token_type': 'Bearer',
            'expires_in': 900,
            'refresh_token': 'refresh-1',
            'refresh_expires_in': 5184000,
            'server_time': '2026-08-03T12:00:00Z',
          },
          'user': {'id': 'u1', 'username': 'agente1', 'display_name': null, 'org_id': 'org1', 'roles': ['agent']},
        }, 200);
      });

      final result = await ctx.client.login(username: 'agente1', password: 'secret', deviceInfo: _deviceInfo);

      expect(result, isA<AuthOk<LoginResponse>>());
      final response = (result as AuthOk<LoginResponse>).value;
      expect(response.tokens.accessToken, 'access-1');
      expect(response.user.username, 'agente1');
    });

    test('401 -> invalidCredentials (nunca unauthorized, en login no hay sesión que expirar)', () async {
      final ctx = _clientWith(
        (options) => jsonResponseBody({'code': 'invalid_credentials', 'message': 'bad'}, 401),
      );

      final result = await ctx.client.login(username: 'agente1', password: 'wrong', deviceInfo: _deviceInfo);

      expect(result, const AuthResult<LoginResponse>.err(AuthError.invalidCredentials()));
    });

    test('sin conexión (adapter lanza) -> AuthError.network', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://visitacampo.test'));
      dio.httpClientAdapter = FakeHttpClientAdapter((options) {
        throw const SocketExceptionStub();
      });
      final client = AuthApiClient(dio);

      final result = await client.login(username: 'agente1', password: 'secret', deviceInfo: _deviceInfo);

      expect(result, isA<AuthErr<LoginResponse>>());
      expect((result as AuthErr<LoginResponse>).error, isA<AuthNetworkError>());
    });
  });

  group('AuthApiClient.refresh', () {
    test('200 -> parsea TokenPair', () async {
      final ctx = _clientWith((options) {
        final body = options.data as Map<String, dynamic>;
        expect(body['refresh_token'], 'refresh-1');
        expect(body['device_id'], 'device-1');
        return jsonResponseBody({
          'access_token': 'access-2',
          'token_type': 'Bearer',
          'expires_in': 900,
          'refresh_token': 'refresh-2',
          'refresh_expires_in': 5184000,
          'server_time': '2026-08-03T12:05:00Z',
        }, 200);
      });

      final result = await ctx.client.refresh(refreshToken: 'refresh-1', deviceId: 'device-1');

      expect(result, isA<AuthOk<TokenPair>>());
      expect((result as AuthOk<TokenPair>).value.accessToken, 'access-2');
    });

    test('401 -> unauthorized (no invalidCredentials: refresh no es login)', () async {
      final ctx = _clientWith(
        (options) => jsonResponseBody({'code': 'unauthenticated', 'message': 'expired'}, 401),
      );

      final result = await ctx.client.refresh(refreshToken: 'stale', deviceId: 'device-1');

      expect(result, const AuthResult<TokenPair>.err(AuthError.unauthorized()));
    });

    test('cuerpo malformado (falta un campo requerido) -> malformedResponse, nunca una excepción', () async {
      final ctx = _clientWith((options) => jsonResponseBody({'access_token': 'a'}, 200));

      final result = await ctx.client.refresh(refreshToken: 'r', deviceId: 'device-1');

      expect(result, isA<AuthErr<TokenPair>>());
      expect((result as AuthErr<TokenPair>).error, isA<AuthMalformedResponse>());
    });
  });

  group('AuthApiClient.logout', () {
    test('204 -> ok(null) y envía Authorization: Bearer', () async {
      final ctx = _clientWith((options) {
        expect(options.headers['Authorization'], 'Bearer access-1');
        return ResponseBody.fromString('', 204);
      });

      final result = await ctx.client.logout(accessToken: 'access-1', refreshToken: 'refresh-1');

      expect(result, const AuthResult<void>.ok(null));
    });
  });

  group('AuthApiClient.serverInfo', () {
    test('200 -> parsea ServerInfo y envía Authorization: Bearer', () async {
      final ctx = _clientWith((options) {
        expect(options.headers['Authorization'], 'Bearer access-1');
        return jsonResponseBody({
          'api_version': 'v1',
          'schema_version': 1,
          'min_supported_schema_version': 1,
          'server_time': '2026-08-03T12:00:00Z',
          'capabilities': {
            'sync_push_max_ops': 500,
            'sync_push_max_bytes': 5242880,
            'sync_pull_max_limit': 1000,
            'attachment_max_bytes': 20971520,
            'attachment_allowed_mime': ['image/jpeg'],
          },
        }, 200);
      });

      final result = await ctx.client.serverInfo(accessToken: 'access-1');

      expect(result, isA<AuthOk<ServerInfo>>());
      expect((result as AuthOk<ServerInfo>).value.schemaVersion, 1);
    });

    test('401 -> unauthorized', () async {
      final ctx = _clientWith(
        (options) => jsonResponseBody({'code': 'unauthenticated', 'message': 'expired'}, 401),
      );

      final result = await ctx.client.serverInfo(accessToken: 'stale');

      expect(result, const AuthResult<ServerInfo>.err(AuthError.unauthorized()));
    });
  });
}

/// Cualquier `Object` no-`DioException` que el adapter lance, Dio lo envuelve
/// en un `DioException` de tipo `unknown` sin `response` — exactamente el
/// caso "sin conexión" que `_mapError` traduce a `AuthError.network`. No hace
/// falta un `SocketException` real de `dart:io` para probar esa rama.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'SocketExceptionStub: connection refused';
}
