// `CaptureScreen` (Paso 22): plantilla de la caché local → formulario dinámico
// → foto, GPS → guardado offline en una sola transacción. Sin red y sin
// hardware: GPS y cámara son dobles (`MockGnss` del plan).
import 'dart:convert';
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

class MockGnss implements LocationSource {
  const MockGnss(this.fix);
  final LocationFix? fix;

  @override
  Future<LocationFix?> getCurrentFix() async => fix;
}

class FakeCamera implements PhotoCapture {
  var _taken = 0;

  @override
  Future<CapturedPhoto?> takePhoto() async {
    final n = _taken++;
    return CapturedPhoto(
      file: File.fromUri(Uri.file('/tmp/foto-$n.jpg')),
      sha256: n.toRadixString(16).padLeft(64, '0'),
      sizeBytes: 1024,
      mime: 'image/jpeg',
    );
  }
}

TokenPair _tokenPair() => TokenPair(
  accessToken: 'access-1',
  tokenType: 'Bearer',
  expiresIn: 900,
  refreshToken: 'refresh-1',
  refreshExpiresIn: 5184000,
  serverTime: DateTime.utc(2026, 10, 17, 12),
);

const _user = UserProfile(id: 'user-1', username: 'agente1', orgId: 'org-1', roles: ['agent']);

Map<String, dynamic> templateRow() => {
  'id': 'tv-1',
  'org_id': 'org-1',
  'version': 1,
  'change_seq': 1,
  'deleted_at': null,
  'template_id': 'tpl-1',
  'name': 'Inspección',
  'version_number': 1,
  'published_at': '2026-10-01T00:00:00Z',
  'definition': {
    'fields': [
      {
        'key': 'tiene_planta',
        'type': 'boolean',
        'label': {'es': '¿Hay planta?'},
        'required': true,
      },
      {
        'key': 'altura_cm',
        'type': 'number',
        'label': {'es': 'Altura (cm)'},
        'visible_if': {'op': 'eq', 'field': 'tiene_planta', 'value': true},
      },
      {
        'key': 'foto_planta',
        'type': 'photo',
        'label': {'es': 'Foto de la planta'},
        'required': true,
        'visible_if': {'op': 'eq', 'field': 'tiene_planta', 'value': true},
      },
    ],
  },
};

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<AppDependencies> buildDependencies({bool withTemplate = true, LocationFix? fix}) async {
    final transport = FakeAuthTransport()
      ..loginResponses.add(AuthResult.ok(LoginResponse(tokens: _tokenPair(), user: _user)));
    final controller = AuthController(transport: transport, tokenStore: FakeTokenStore(), deviceId: 'device-1');
    await controller.login(
      username: 'agente1',
      password: 'secret',
      deviceInfo: const DeviceInfo(deviceId: 'device-1', platform: 'android', appVersion: '1.0.0'),
    );
    final dependencies = AppDependencies(
      database: db,
      dio: Dio(),
      authController: controller,
      deviceId: 'device-1',
      locationSource: MockGnss(fix),
      photoCapture: FakeCamera(),
    );
    if (withTemplate) await dependencies.formTemplates.upsertFromServerRow(templateRow());
    return dependencies;
  }

  Future<void> pumpCapture(WidgetTester tester, AppDependencies dependencies) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
        child: testApp(const CaptureScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('captura completa offline: formulario, foto del campo, GPS y foto adicional', (tester) async {
    final dependencies = await buildDependencies(fix: const LocationFix(lat: 4.6, lon: -74.08, accuracyM: 4.2));
    await pumpCapture(tester, dependencies);

    // Una sola plantilla: se abre sola, con el formulario dinámico.
    expect(find.text('¿Hay planta? *'), findsOneWidget);
    expect(find.text('Altura (cm)'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Sí'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Altura (cm)'), '35');
    await tester.tap(find.text('Tomar foto'));
    await tester.pumpAndSettle();
    expect(find.text('Foto adjunta.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('capture_get_location_button')));
    await tester.pumpAndSettle();
    expect(find.text('lat: 4.6, lon: -74.08 (±4 m)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('capture_add_photo_button')));
    await tester.pumpAndSettle();
    expect(find.text('1 foto adicional'), findsOneWidget);

    await tester.tap(find.byKey(const Key('capture_save_button')));
    await tester.pumpAndSettle();

    // Todo quedó en la BD local, sin red: la UI puede mostrarlo ya.
    final visit = await db.select(db.visits).getSingle();
    expect(visit.templateVersionId, 'tv-1');
    expect(visit.lat, 4.6);
    final answers = jsonDecode(visit.answersJson) as Map<String, dynamic>;
    expect(answers['tiene_planta'], true);
    expect(answers['altura_cm'], 35);
    final attachments = await db.select(db.visitAttachments).get();
    expect(attachments.map((a) => a.id), contains(answers['foto_planta']));
    expect(attachments, hasLength(2), reason: 'la del campo y la adicional');
    expect(await db.select(db.attachmentQueue).get(), hasLength(2));
    expect((await db.select(db.outboxOps).get()).map((o) => o.entity), [
      'visit',
      'visit_attachment',
      'visit_attachment',
    ]);
  });

  testWidgets('con campos obligatorios sin responder no guarda nada', (tester) async {
    final dependencies = await buildDependencies();
    await pumpCapture(tester, dependencies);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Sí'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('capture_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Revisa los campos marcados antes de guardar.'), findsOneWidget);
    expect(find.text('Este campo es obligatorio.'), findsOneWidget, reason: 'la foto obligatoria');
    expect(await db.select(db.visits).get(), isEmpty);
    expect(await db.select(db.outboxOps).get(), isEmpty);
  });

  testWidgets('sin plantillas en el dispositivo pide sincronizar', (tester) async {
    final dependencies = await buildDependencies(withTemplate: false);
    await pumpCapture(tester, dependencies);

    expect(find.byKey(const Key('capture_no_templates')), findsOneWidget);
    expect(find.byKey(const Key('capture_save_button')), findsNothing);
  });

  testWidgets('sin GPS se avisa y se puede guardar igual', (tester) async {
    final dependencies = await buildDependencies();
    await pumpCapture(tester, dependencies);

    await tester.tap(find.byKey(const Key('capture_get_location_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo obtener la ubicación'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'No'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('capture_save_button')));
    await tester.pumpAndSettle();
    final visit = await db.select(db.visits).getSingle();
    expect(visit.lat, isNull);
  });
}
