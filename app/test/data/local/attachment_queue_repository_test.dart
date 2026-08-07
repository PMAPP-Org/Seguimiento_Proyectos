// `AttachmentQueueRepository` — Tarea 6 del plan de despliegue del demo.
// Envuelve la tabla `AttachmentQueue` (`data/local/tables.dart`, Paso 11) que
// hasta ahora nadie escribía: la Tarea 7 (subida manual) leerá estas filas.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/data/local/attachment_queue_repository.dart';
import 'package:visitacampo/data/local/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('enqueue inserta una fila en estado pending', () async {
    final repository = AttachmentQueueRepository(db);
    final now = DateTime.utc(2026, 8, 6);

    await repository.enqueue(sha256: 'a' * 64, localPath: '/tmp/foto.jpg', now: now);

    final rows = await db.select(db.attachmentQueue).get();
    expect(rows, hasLength(1));
    expect(rows.single.sha256, 'a' * 64);
    expect(rows.single.localPath, '/tmp/foto.jpg');
    expect(rows.single.state, 'pending');
    // Drift guarda `DateTime` como epoch y lo reconstruye en hora local al
    // leer (mismo instante, `isUtc` distinto) — Dart's `DateTime.==` sí
    // distingue `isUtc`, así que hay que normalizar antes de comparar.
    expect(rows.single.createdAt.toUtc(), now);
  });

  test('enqueue es idempotente para el mismo sha256 (mismo contenido, no duplica)', () async {
    final repository = AttachmentQueueRepository(db);
    final now = DateTime.utc(2026, 8, 6);

    await repository.enqueue(sha256: 'b' * 64, localPath: '/tmp/1.jpg', now: now);
    await repository.enqueue(sha256: 'b' * 64, localPath: '/tmp/2.jpg', now: now);

    final rows = await db.select(db.attachmentQueue).get();
    expect(rows, hasLength(1));
  });
}
