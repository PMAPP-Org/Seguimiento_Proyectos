// Tests de `AuthController` (Paso 13, tareas 3/4) — verificación explícita
// del plan: "login exitoso guarda tokens; login fallido no persiste nada;
// 401 dispara exactamente un intento de refresh, no un loop" (esta última
// mitad se prueba a nivel de `AuthInterceptor`, ver `auth_interceptor_test.dart`;
// aquí se prueba el mecanismo de single-flight de `refreshOnce()` en sí).
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/auth/auth_controller.dart';
import 'package:visitacampo/core/auth/auth_models.dart';
import 'package:visitacampo/core/auth/auth_result.dart';
import 'package:visitacampo/core/auth/auth_state.dart';

import 'fake_auth_transport.dart';
import 'fake_token_store.dart';

const _deviceInfo = DeviceInfo(deviceId: 'device-1', platform: 'android', appVersion: '1.0.0');

TokenPair _tokenPair({String access = 'access-1', String refresh = 'refresh-1', int expiresIn = 900}) {
  return TokenPair(
    accessToken: access,
    tokenType: 'Bearer',
    expiresIn: expiresIn,
    refreshToken: refresh,
    refreshExpiresIn: 5184000,
    serverTime: DateTime.utc(2026, 8, 3, 12),
  );
}

const _user = UserProfile(id: 'u1', username: 'agente1', orgId: 'org1', roles: ['agent']);

void main() {
  group('AuthController.login', () {
    test('éxito: guarda el refresh token y queda Authenticated con el access token en memoria', () async {
      final transport = FakeAuthTransport()
        ..loginResponses.add(AuthResult.ok(LoginResponse(tokens: _tokenPair(), user: _user)));
      final tokenStore = FakeTokenStore();
      final controller = AuthController(transport: transport, tokenStore: tokenStore, deviceId: 'device-1');

      final result = await controller.login(username: 'agente1', password: 'secret', deviceInfo: _deviceInfo);

      expect(result, isA<AuthOk<UserProfile>>());
      expect(controller.accessToken, 'access-1');
      expect(await tokenStore.readRefreshToken('device-1'), 'refresh-1');
      expect(controller.state, isA<Authenticated>());
      final state = controller.state as Authenticated;
      expect(state.user, _user);
    });

    test('fallo: no persiste ningún token y el estado sigue sin autenticar', () async {
      final transport = FakeAuthTransport()
        ..loginResponses.add(const AuthResult.err(AuthError.invalidCredentials()));
      final tokenStore = FakeTokenStore();
      final controller = AuthController(transport: transport, tokenStore: tokenStore, deviceId: 'device-1');

      final result = await controller.login(username: 'agente1', password: 'wrong', deviceInfo: _deviceInfo);

      expect(result, isA<AuthErr<UserProfile>>());
      expect(controller.accessToken, isNull);
      expect(tokenStore.isEmpty, isTrue);
      expect(controller.state, isA<Unauthenticated>());
    });
  });

  group('AuthController.refreshOnce', () {
    test('éxito: rota el access token y actualiza el refresh token persistido', () async {
      final transport = FakeAuthTransport()
        ..loginResponses.add(AuthResult.ok(LoginResponse(tokens: _tokenPair(), user: _user)))
        ..refreshResponses.add(
          AuthResult.ok(_tokenPair(access: 'access-2', refresh: 'refresh-2', expiresIn: 900)),
        );
      final tokenStore = FakeTokenStore();
      final controller = AuthController(transport: transport, tokenStore: tokenStore, deviceId: 'device-1');
      await controller.login(username: 'agente1', password: 'secret', deviceInfo: _deviceInfo);

      final refreshed = await controller.refreshOnce();

      expect(refreshed, isTrue);
      expect(controller.accessToken, 'access-2');
      expect(await tokenStore.readRefreshToken('device-1'), 'refresh-2');
      expect(controller.state, isA<Authenticated>());
    });

    test('llamadas concurrentes comparten un único refresh en vuelo (single-flight)', () async {
      final transport = FakeAuthTransport()
        ..loginResponses.add(AuthResult.ok(LoginResponse(tokens: _tokenPair(), user: _user)))
        ..refreshResponses.add(AuthResult.ok(_tokenPair(access: 'access-2', refresh: 'refresh-2')));
      final tokenStore = FakeTokenStore();
      final controller = AuthController(transport: transport, tokenStore: tokenStore, deviceId: 'device-1');
      await controller.login(username: 'agente1', password: 'secret', deviceInfo: _deviceInfo);

      final results = await Future.wait([controller.refreshOnce(), controller.refreshOnce(), controller.refreshOnce()]);

      expect(results, everyElement(isTrue));
      expect(transport.refreshCallCount, 1);
    });

    test('fallo: transiciona a Disconnected sin tocar la outbox (este módulo no la conoce)', () async {
      final transport = FakeAuthTransport()
        ..loginResponses.add(AuthResult.ok(LoginResponse(tokens: _tokenPair(), user: _user)))
        ..refreshResponses.add(const AuthResult.err(AuthError.unauthorized()));
      final tokenStore = FakeTokenStore();
      final controller = AuthController(transport: transport, tokenStore: tokenStore, deviceId: 'device-1');
      await controller.login(username: 'agente1', password: 'secret', deviceInfo: _deviceInfo);

      final refreshed = await controller.refreshOnce();

      expect(refreshed, isFalse);
      expect(controller.accessToken, isNull);
      expect(controller.state, isA<Disconnected>());
    });

    test('sin refresh token guardado: Disconnected sin llamar al transporte', () async {
      final transport = FakeAuthTransport();
      final tokenStore = FakeTokenStore();
      final controller = AuthController(transport: transport, tokenStore: tokenStore, deviceId: 'device-1');

      final refreshed = await controller.refreshOnce();

      expect(refreshed, isFalse);
      expect(transport.refreshCallCount, 0);
      expect(controller.state, isA<Disconnected>());
    });
  });

  group('AuthController.logout', () {
    test('limpia el token en memoria y el refresh token persistido', () async {
      final transport = FakeAuthTransport()
        ..loginResponses.add(AuthResult.ok(LoginResponse(tokens: _tokenPair(), user: _user)))
        ..logoutResponses.add(const AuthResult.ok(null));
      final tokenStore = FakeTokenStore();
      final controller = AuthController(transport: transport, tokenStore: tokenStore, deviceId: 'device-1');
      await controller.login(username: 'agente1', password: 'secret', deviceInfo: _deviceInfo);

      await controller.logout();

      expect(controller.accessToken, isNull);
      expect(await tokenStore.readRefreshToken('device-1'), isNull);
      expect(controller.state, isA<Unauthenticated>());
      expect(transport.logoutCallCount, 1);
    });

    test('sin sesión previa: limpia el estado local sin llamar al servidor', () async {
      final transport = FakeAuthTransport();
      final tokenStore = FakeTokenStore();
      final controller = AuthController(transport: transport, tokenStore: tokenStore, deviceId: 'device-1');

      await controller.logout();

      expect(transport.logoutCallCount, 0);
      expect(controller.state, isA<Unauthenticated>());
    });
  });
}
