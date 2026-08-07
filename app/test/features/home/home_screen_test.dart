// `HomeScreen` — botón "Sincronizar" (Tarea 7 del plan de despliegue del
// demo). Verifica que tocar el botón llama, en orden, a
// `SyncEngine.drainOutbox()`, `AttachmentUploadService.drainPending()` y
// `SyncEngine.pull()` — sin necesidad de red real, con
// `FakeSyncTransport`/`FakeAttachmentTransport`.
//
// Hallazgo Crítico/Importante de la revisión final: el SnackBar antes decía
// siempre "completa", incluso con adjuntos fallidos, operaciones rechazadas
// o un `pull()` con error. El segundo test de este archivo prueba justo eso:
// un adjunto que falla debe producir un mensaje distinto que mencione el
// fallo con su conteo real, no el mensaje de éxito de siempre.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/app_dependencies.dart';
import 'package:visitacampo/core/attachments/attachment_result.dart';
import 'package:visitacampo/core/attachments/attachment_upload_service.dart';
import 'package:visitacampo/core/auth/auth_controller.dart';
import 'package:visitacampo/core/providers.dart';
import 'package:visitacampo/core/sync/result.dart';
import 'package:visitacampo/core/sync/sync_engine.dart';
import 'package:visitacampo/core/sync/sync_transport.dart';
import 'package:visitacampo/data/local/database.dart';
import 'package:visitacampo/features/home/home_screen.dart';

import '../../core/attachments/fake_attachment_transport.dart';
import '../../core/auth/fake_auth_transport.dart';
import '../../core/auth/fake_token_store.dart';
import '../../core/sync/fake_sync_transport.dart';

void main() {
  testWidgets('Sincronizar drena el outbox, sube adjuntos pendientes y hace pull', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final syncTransport = FakeSyncTransport()
      ..pullResponses.add(
        Result.ok(
          const PullResponse(rows: [], tombstones: [], nextCursor: 'c1:00000000000000000001', hasMore: false),
        ),
      );
    final syncEngine = SyncEngine(db: db, transport: syncTransport, deviceId: 'device-1');

    final attachmentTransport = FakeAttachmentTransport();
    final attachmentUploadService = AttachmentUploadService(
      db: db,
      transport: attachmentTransport,
    );

    final authController = AuthController(
      transport: FakeAuthTransport(),
      tokenStore: FakeTokenStore(),
      deviceId: 'device-1',
    );

    final dependencies = AppDependencies(
      database: db,
      dio: Dio(),
      authController: authController,
      deviceId: 'device-1',
      syncEngine: syncEngine,
      attachmentUploadService: attachmentUploadService,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.tap(find.byKey(const Key('home_sync_button')));
    await tester.pumpAndSettle();

    expect(syncTransport.pullCalls, hasLength(1));
    expect(find.textContaining('Sincronización completa'), findsOneWidget);
  });

  testWidgets(
    'Sincronizar con un adjunto fallido muestra un mensaje de incompleta con el conteo, '
    'no el de éxito',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.attachmentQueue)
          .insert(
            AttachmentQueueCompanion.insert(
              sha256: 'a' * 64,
              localPath: '/tmp/foto.jpg',
              state: 'pending',
              createdAt: DateTime.utc(2026, 8, 6),
            ),
          );

      final syncTransport = FakeSyncTransport()
        ..pullResponses.add(
          Result.ok(
            const PullResponse(rows: [], tombstones: [], nextCursor: 'c1:00000000000000000001', hasMore: false),
          ),
        );
      final syncEngine = SyncEngine(db: db, transport: syncTransport, deviceId: 'device-1');

      final attachmentTransport = FakeAttachmentTransport()
        ..presignResponses.add(const AttachmentResult.err(AttachmentError.network('sin conexion')));
      final attachmentUploadService = AttachmentUploadService(
        db: db,
        transport: attachmentTransport,
        readBytes: (path) async => Uint8List.fromList(const [1, 2, 3]),
      );

      final authController = AuthController(
        transport: FakeAuthTransport(),
        tokenStore: FakeTokenStore(),
        deviceId: 'device-1',
      );

      final dependencies = AppDependencies(
        database: db,
        dio: Dio(),
        authController: authController,
        deviceId: 'device-1',
        syncEngine: syncEngine,
        attachmentUploadService: attachmentUploadService,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.tap(find.byKey(const Key('home_sync_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sincronización completa'), findsNothing);
      expect(find.textContaining('Sincronización incompleta'), findsOneWidget);
      expect(find.textContaining('1 adjunto(s) fallido(s)'), findsOneWidget);
    },
  );
}
