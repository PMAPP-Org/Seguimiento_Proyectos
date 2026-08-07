// `AttachmentUploadService` — Tarea 7 del plan de despliegue del demo.
// Orquesta presign→PUT→commit para cada fila `pending` de `AttachmentQueue`
// (`data/local/tables.dart`, Paso 11, sin lector hasta ahora). Sin red real:
// `FakeAttachmentTransport` programa las tres respuestas.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/attachments/attachment_result.dart';
import 'package:visitacampo/core/attachments/attachment_transport.dart';
import 'package:visitacampo/core/attachments/attachment_upload_service.dart';
import 'package:visitacampo/data/local/database.dart';

import 'fake_attachment_transport.dart';

void main() {
  late AppDatabase db;
  late FakeAttachmentTransport transport;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    transport = FakeAttachmentTransport();
  });

  tearDown(() => db.close());

  Future<List<int>> fakeReadBytes(String path) async => List<int>.filled(10, 1);

  test('sube y confirma un adjunto pending, y lo marca uploaded', () async {
    await db
        .into(db.attachmentQueue)
        .insert(
          AttachmentQueueCompanion.insert(
            sha256: 'd' * 64,
            localPath: '/tmp/foto.jpg',
            state: 'pending',
            createdAt: DateTime.utc(2026, 8, 6),
          ),
        );
    transport.presignResponses.add(
      AttachmentResult.ok(
        const PresignData(alreadyPresent: false, uploadUrl: 'https://blob.test/put', requiredHeaders: {}),
      ),
    );
    transport.uploadResponses.add(const AttachmentResult.ok(null));
    transport.commitResponses.add(const AttachmentResult.ok(null));

    final service = AttachmentUploadService(db: db, transport: transport, readBytes: fakeReadBytes);
    final report = await service.drainPending();

    expect(report.uploaded, 1);
    expect(report.failed, 0);
    final row = await (db.select(db.attachmentQueue)
          ..where((t) => t.sha256.equals('d' * 64)))
        .getSingle();
    expect(row.state, 'uploaded');
  });

  test('already_present salta la subida y confirma directo', () async {
    await db
        .into(db.attachmentQueue)
        .insert(
          AttachmentQueueCompanion.insert(
            sha256: 'e' * 64,
            localPath: '/tmp/foto2.jpg',
            state: 'pending',
            createdAt: DateTime.utc(2026, 8, 6),
          ),
        );
    transport.presignResponses.add(
      AttachmentResult.ok(const PresignData(alreadyPresent: true, uploadUrl: null, requiredHeaders: null)),
    );
    transport.commitResponses.add(const AttachmentResult.ok(null));

    final service = AttachmentUploadService(db: db, transport: transport, readBytes: fakeReadBytes);
    final report = await service.drainPending();

    expect(report.uploaded, 1);
    expect(transport.uploadResponses, isEmpty, reason: 'upload() no debe programarse ni consumirse');
  });

  test('un fallo de presign marca la fila failed sin detener el resto del lote', () async {
    await db
        .into(db.attachmentQueue)
        .insert(
          AttachmentQueueCompanion.insert(
            sha256: 'f' * 64,
            localPath: '/tmp/foto3.jpg',
            state: 'pending',
            createdAt: DateTime.utc(2026, 8, 6),
          ),
        );
    transport.presignResponses.add(
      const AttachmentResult.err(AttachmentError.network('sin conexion')),
    );

    final service = AttachmentUploadService(db: db, transport: transport, readBytes: fakeReadBytes);
    final report = await service.drainPending();

    expect(report.uploaded, 0);
    expect(report.failed, 1);
    final row = await (db.select(db.attachmentQueue)
          ..where((t) => t.sha256.equals('f' * 64)))
        .getSingle();
    expect(row.state, 'failed');
  });

  test(
    'un archivo local ilegible (borrado/sin permiso) marca la fila failed '
    'sin propagar la excepción ni detener el resto del lote',
    () async {
      await db
          .into(db.attachmentQueue)
          .insert(
            AttachmentQueueCompanion.insert(
              sha256: 'g' * 64,
              localPath: '/ruta/que/no/existe/foto-fantasma.jpg',
              state: 'pending',
              createdAt: DateTime.utc(2026, 8, 6),
            ),
          );
      // No se programa ninguna respuesta de transporte: si la excepción de
      // lectura se filtrara, presign() nunca se invocaría y el test fallaría
      // igual (ya sea por la excepción sin capturar o por un fallo distinto).
      // Sin `readBytes` override: usa el lector real `File.readAsBytes()`
      // sobre una ruta inexistente, tal como ocurriría en un dispositivo real.
      final service = AttachmentUploadService(db: db, transport: transport);

      // Si la excepción de lectura se filtrara sin capturar, este `await`
      // relanzaría y el test fallaría aquí mismo, en vez de continuar hacia
      // las aserciones de abajo.
      final report = await service.drainPending();

      expect(report.uploaded, 0);
      expect(report.failed, 1);
      final row = await (db.select(db.attachmentQueue)
            ..where((t) => t.sha256.equals('g' * 64)))
          .getSingle();
      expect(row.state, 'failed');
    },
  );
}
