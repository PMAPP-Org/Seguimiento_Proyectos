// Tests de `AuthInterceptor` (Paso 13, tarea 4) — verificación explícita del
// plan: "401 dispara exactamente un intento de refresh, no un loop". Usa un
// `Dio` real con un `HttpClientAdapter` falso (sin red) para probar el
// mecanismo tal como corre en producción: el interceptor reintenta sobre el
// mismo `Dio`, no sobre un mock de la request.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/auth/auth_controller.dart';
import 'package:visitacampo/core/auth/auth_models.dart';
import 'package:visitacampo/core/auth/auth_result.dart';
import 'package:visitacampo/core/auth/auth_state.dart';
import 'package:visitacampo/data/http/auth_interceptor.dart';

import 'fake_auth_transport.dart';
import 'fake_http_client_adapter.dart';
import 'fake_token_store.dart';

const _deviceInfo = DeviceInfo(deviceId: 'device-1', platform: 'android', appVersion: '1.0.0');
const _user = UserProfile(id: 'u1', username: 'agente1', orgId: 'org1', roles: ['agent']);

TokenPair _tokenPair(String access, String refresh) => TokenPair(
  accessToken: access,
  tokenType: 'Bearer',
  expiresIn: 900,
  refreshToken: refresh,
  refreshExpiresIn: 5184000,
  serverTime: DateTime.utc(2026, 8, 3, 12),
);

Future<AuthController> _loggedInController(FakeAuthTransport transport) async {
  transport.loginResponses.add(AuthResult.ok(LoginResponse(tokens: _tokenPair('access-old', 'refresh-old'), user: _user)));
  final controller = AuthController(
    transport: transport,
    tokenStore: FakeTokenStore(),
    deviceId: 'device-1',
  );
  await controller.login(username: 'agente1', password: 'secret', deviceInfo: _deviceInfo);
  return controller;
}

Dio _dioWith(FakeHttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://visitacampo.test'));
  dio.httpClientAdapter = adapter;
  return dio;
}

Future<Response<dynamic>> _callProtected(Dio dio, AuthController controller) {
  return dio.get<dynamic>(
    '/v1/protected',
    options: Options(headers: {'Authorization': 'Bearer ${controller.accessToken}'}),
  );
}

void main() {
  group('AuthInterceptor', () {
    test('401 -> refresh exitoso -> reintenta una vez con el token nuevo', () async {
      final transport = FakeAuthTransport();
      final controller = await _loggedInController(transport);
      transport.refreshResponses.add(AuthResult.ok(_tokenPair('access-new', 'refresh-new')));

      var callCount = 0;
      final adapter = FakeHttpClientAdapter((options) {
        callCount++;
        if (callCount == 1) {
          return jsonResponseBody({'code': 'unauthenticated', 'message': 'expired'}, 401);
        }
        return jsonResponseBody({'ok': true}, 200);
      });
      final dio = _dioWith(adapter);
      dio.interceptors.add(AuthInterceptor(dio: dio, controller: controller));

      final response = await _callProtected(dio, controller);

      expect(response.statusCode, 200);
      expect(transport.refreshCallCount, 1);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[1].headers['Authorization'], 'Bearer access-new');
      expect(controller.accessToken, 'access-new');
      expect(controller.state, isA<Authenticated>());
    });

    test('401 -> refresh falla -> Disconnected, propaga el 401 original sin reintentar', () async {
      final transport = FakeAuthTransport();
      final controller = await _loggedInController(transport);
      transport.refreshResponses.add(const AuthResult.err(AuthError.unauthorized()));

      final adapter = FakeHttpClientAdapter(
        (options) => jsonResponseBody({'code': 'unauthenticated', 'message': 'expired'}, 401),
      );
      final dio = _dioWith(adapter);
      dio.interceptors.add(AuthInterceptor(dio: dio, controller: controller));

      await expectLater(
        _callProtected(dio, controller),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 401)),
      );
      expect(transport.refreshCallCount, 1);
      expect(adapter.requests, hasLength(1));
      expect(controller.state, isA<Disconnected>());
    });

    test('la request reintentada también recibe 401 -> no dispara un segundo refresh (sin loop)', () async {
      final transport = FakeAuthTransport();
      final controller = await _loggedInController(transport);
      transport.refreshResponses.add(AuthResult.ok(_tokenPair('access-new', 'refresh-new')));

      final adapter = FakeHttpClientAdapter(
        (options) => jsonResponseBody({'code': 'unauthenticated', 'message': 'expired'}, 401),
      );
      final dio = _dioWith(adapter);
      dio.interceptors.add(AuthInterceptor(dio: dio, controller: controller));

      await expectLater(
        _callProtected(dio, controller),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 401)),
      );
      // Refresh se intentó una sola vez a pesar de que la request reintentada
      // también falló con 401 — la bandera `_retriedFlag` corta el loop.
      expect(transport.refreshCallCount, 1);
      expect(adapter.requests, hasLength(2));
    });

    test('un 401 en /v1/auth/login no dispara refresh (no existe sesión que refrescar)', () async {
      final transport = FakeAuthTransport();
      final controller = AuthController(transport: transport, tokenStore: FakeTokenStore(), deviceId: 'device-1');

      final adapter = FakeHttpClientAdapter(
        (options) => jsonResponseBody({'code': 'invalid_credentials', 'message': 'bad creds'}, 401),
      );
      final dio = _dioWith(adapter);
      dio.interceptors.add(AuthInterceptor(dio: dio, controller: controller));

      await expectLater(
        dio.post<dynamic>('/v1/auth/login', data: {'username': 'x', 'password': 'y'}),
        throwsA(isA<DioException>()),
      );
      expect(transport.refreshCallCount, 0);
      expect(adapter.requests, hasLength(1));
    });
  });
}
