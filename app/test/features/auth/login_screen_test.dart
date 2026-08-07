// `LoginScreen` — Tarea 5 del plan de despliegue del demo. Reutiliza
// `FakeAuthTransport`/`FakeTokenStore` ya construidos para `AuthController`
// (Paso 13) en vez de levantar red real, mismo criterio que
// `test/core/auth/auth_controller_test.dart`.
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/app_dependencies.dart';
import 'package:visitacampo/core/auth/auth_controller.dart';
import 'package:visitacampo/core/auth/auth_models.dart';
import 'package:visitacampo/core/auth/auth_result.dart';
import 'package:visitacampo/core/providers.dart';
import 'package:visitacampo/data/local/database.dart';
import 'package:visitacampo/features/auth/login_screen.dart';
import 'package:visitacampo/features/home/home_screen.dart';

import '../../core/auth/fake_auth_transport.dart';
import '../../core/auth/fake_token_store.dart';

TokenPair _tokenPair() => TokenPair(
  accessToken: 'access-1',
  tokenType: 'Bearer',
  expiresIn: 900,
  refreshToken: 'refresh-1',
  refreshExpiresIn: 5184000,
  serverTime: DateTime.utc(2026, 8, 6, 12),
);

const _user = UserProfile(id: 'u1', username: 'agente1', orgId: 'org1', roles: ['agent']);

AppDependencies _buildDependencies(FakeAuthTransport transport) {
  final controller = AuthController(
    transport: transport,
    tokenStore: FakeTokenStore(),
    deviceId: 'device-1',
  );
  return AppDependencies(
    database: AppDatabase.forTesting(NativeDatabase.memory()),
    dio: Dio(),
    authController: controller,
    deviceId: 'device-1',
  );
}

void main() {
  testWidgets('login exitoso navega a HomeScreen', (tester) async {
    final transport = FakeAuthTransport()
      ..loginResponses.add(AuthResult.ok(LoginResponse(tokens: _tokenPair(), user: _user)));
    final dependencies = _buildDependencies(transport);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(find.byKey(const Key('login_username_field')), 'agente1');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'secret');
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('login fallido muestra un mensaje y se queda en LoginScreen', (tester) async {
    final transport = FakeAuthTransport()
      ..loginResponses.add(const AuthResult.err(AuthError.invalidCredentials()));
    final dependencies = _buildDependencies(transport);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(find.byKey(const Key('login_username_field')), 'agente1');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'mal');
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
  });
}
