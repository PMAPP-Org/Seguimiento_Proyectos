// `HomeScreen` — botón "Sincronizar" (Tarea 7 del plan de despliegue del
// demo). Verifica que tocar el botón llama, en orden, a
// `SyncEngine.drainOutbox()`, `AttachmentUploadService.drainPending()` y
// `SyncEngine.pull()` — sin necesidad de red real, con
// `FakeSyncTransport`/`FakeAttachmentTransport`.
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/app_dependencies.dart';
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
}
