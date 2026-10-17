// `CaptureScreen` — Tarea 6 del plan de despliegue del demo. Formulario
// FIJO (no el renderer dinámico del Paso 21, diferido) + GPS + una foto,
// persistidos en `visits`/`outbox_ops`/`attachment_queue` a través de
// `SyncEngine.enqueueVisitOp` (Paso 12) y `AttachmentQueueRepository`
// (Tarea 6, Step 6) — ambos ya construidos antes de esta pantalla.
//
// Desviación del texto original del brief: `AppDependencies.authController`
// debe estar en `Authenticated` para que `CaptureScreen._save()` no corte
// temprano (mira `authState is! Authenticated`) — el brief no llamaba a
// `controller.login()` en `buildDependencies()`, así que `state` se quedaba
// en `Unauthenticated` y `_save()` nunca escribía nada. Se corrige aquí
// autenticando primero, mismo patrón que `test/features/auth/
// login_screen_test.dart` (cola una respuesta en `FakeAuthTransport` y
// llama a `login()` antes de montar el widget).
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:visitacampo/core/app_dependencies.dart';
import 'package:visitacampo/core/auth/auth_controller.dart';
import 'package:visitacampo/core/auth/auth_models.dart';
import 'package:visitacampo/core/auth/auth_result.dart';
import 'package:visitacampo/core/capture/photo_capture.dart';
import 'package:visitacampo/core/location/location_source.dart';
import 'package:visitacampo/core/providers.dart';
import 'package:visitacampo/data/local/database.dart';
import 'package:visitacampo/features/capture/capture_screen.dart';

import '../../core/auth/fake_auth_transport.dart';
import '../../core/auth/fake_token_store.dart';

import '../../support/test_app.dart';

class _FakeLocationSource implements LocationSource {
  const _FakeLocationSource(this.fix);
  final LocationFix? fix;

  @override
  Future<LocationFix?> getCurrentFix() async => fix;
}

class _FakePhotoCapture implements PhotoCapture {
  _FakePhotoCapture(this.photo);
  final CapturedPhoto? photo;

  @override
  Future<CapturedPhoto?> takePhoto() async => photo;
}

TokenPair _tokenPair() => TokenPair(
  accessToken: 'access-1',
  tokenType: 'Bearer',
  expiresIn: 900,
  refreshToken: 'refresh-1',
  refreshExpiresIn: 5184000,
  serverTime: DateTime.utc(2026, 8, 6, 12),
);

const _user = UserProfile(id: 'user-1', username: 'agente1', orgId: 'org-1', roles: ['agent']);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<AppDependencies> buildDependencies({LocationFix? fix, CapturedPhoto? photo}) async {
    final transport = FakeAuthTransport()
      ..loginResponses.add(AuthResult.ok(LoginResponse(tokens: _tokenPair(), user: _user)));
    final controller = AuthController(
      transport: transport,
      tokenStore: FakeTokenStore(),
      deviceId: 'device-1',
    );
    await controller.login(
      username: 'agente1',
      password: 'secret',
      deviceInfo: const DeviceInfo(deviceId: 'device-1', platform: 'android', appVersion: '1.0.0'),
    );
    return AppDependencies(
      database: db,
      dio: Dio(),
      authController: controller,
      deviceId: 'device-1',
      locationSource: _FakeLocationSource(fix),
      photoCapture: _FakePhotoCapture(photo),
    );
  }

  testWidgets('guardar una visita con GPS y foto encola outbox + attachment_queue', (
    tester,
  ) async {
    final photoFile = File.fromUri(Uri.file('/tmp/foto-demo.jpg'));
    final dependencies = await buildDependencies(
      fix: const LocationFix(lat: 4.6, lon: -74.1, accuracyM: 5),
      photo: CapturedPhoto(
        file: photoFile,
        sha256: 'c' * 64,
        sizeBytes: 1024,
        mime: 'image/jpeg',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
        child: testApp(const CaptureScreen()),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('capture_template_field')),
      '11111111-1111-1111-1111-111111111111',
    );
    await tester.enterText(find.byKey(const Key('capture_altura_field')), '12');
    await tester.enterText(find.byKey(const Key('capture_notas_field')), 'Todo en orden');

    await tester.tap(find.byKey(const Key('capture_get_location_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('4.6'), findsOneWidget);

    await tester.tap(find.byKey(const Key('capture_take_photo_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('foto-demo.jpg'), findsOneWidget);

    await tester.tap(find.byKey(const Key('capture_save_button')));
    await tester.pumpAndSettle();

    final visits = await db.select(db.visits).get();
    expect(visits, hasLength(1));
    expect(visits.single.lat, 4.6);
    expect(visits.single.templateVersionId, '11111111-1111-1111-1111-111111111111');

    final outboxOps = await db.select(db.outboxOps).get();
    expect(outboxOps, hasLength(1));
    expect(outboxOps.single.opType, 'create');
    expect(outboxOps.single.entity, 'visit');

    final attachmentQueue = await db.select(db.attachmentQueue).get();
    expect(attachmentQueue, hasLength(1));
    expect(attachmentQueue.single.sha256, 'c' * 64);
    expect(attachmentQueue.single.state, 'pending');
  });

  testWidgets('guardar una visita sin foto no toca attachment_queue', (tester) async {
    final dependencies = await buildDependencies(fix: null, photo: null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
        child: testApp(const CaptureScreen()),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('capture_template_field')),
      '11111111-1111-1111-1111-111111111111',
    );
    await tester.enterText(find.byKey(const Key('capture_altura_field')), '9');

    await tester.tap(find.byKey(const Key('capture_save_button')));
    await tester.pumpAndSettle();

    final visits = await db.select(db.visits).get();
    expect(visits, hasLength(1));
    expect(visits.single.lat, isNull);

    final attachmentQueue = await db.select(db.attachmentQueue).get();
    expect(attachmentQueue, isEmpty);
  });
}
