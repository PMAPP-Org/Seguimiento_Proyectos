// Paso 11: atomicidad real de "visita + outbox en una sola transacción"
// (RD-04/ADR-002) y humo del esquema Drift.
//
// Usa `AppDatabase.forTesting` con `NativeDatabase.memory()` — sin cifrado a
// propósito: estos tests verifican el esquema y la atomicidad, que son
// independientes de SQLCipher. La verificación de cifrado en disco vive en
// `encryption_smoke_test.dart` (sí corre en este host, con el executor real
// de `createEncryptedExecutor`).
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/data/local/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  VisitsCompanion sampleVisit({required String id}) => VisitsCompanion.insert(
    id: id,
    orgId: 'org-1',
    version: 1,
    templateVersionId: 'template-1',
    answersJson: '{"altura_cm": 12}',
    capturedAt: DateTime.utc(2026, 7, 30, 14, 5, 9),
    deviceId: 'device-1',
    createdBy: 'user-1',
  );

  OutboxOpsCompanion sampleOutboxOp({required String opUuid, required String entityId}) =>
      OutboxOpsCompanion.insert(
        opUuid: opUuid,
        entity: 'visit',
        entityId: entityId,
        opType: 'create',
        payloadJson: '{}',
        state: 'pending',
        createdAt: DateTime.utc(2026, 7, 30, 14, 5, 9),
      );

  group('esquema', () {
    test('crea las tres tablas del Paso 11 sin error', () async {
      expect(await db.select(db.visits).get(), isEmpty);
      expect(await db.select(db.outboxOps).get(), isEmpty);
      expect(await db.select(db.attachmentQueue).get(), isEmpty);
    });
  });

  group('escritor único (RD-04)', () {
    test('AppDatabase.open() rechaza una segunda instancia en el mismo proceso', () async {
      // Primera llamada: se apropia del "slot" de instancia única del
      // proceso (estado estático de AppDatabase, no de este `db` de
      // `setUp`, que usa `forTesting` a propósito para no consumirlo).
      final first = AppDatabase.open(NativeDatabase.memory());
      addTearDown(first.close);

      expect(
        () => AppDatabase.open(NativeDatabase.memory()),
        throwsA(isA<StateError>()),
        reason: 'una segunda conexión de escritura al mismo archivo es '
            'exactamente el bug que RD-04/H-04 (doc 07) documenta en QField',
      );
    });
  });

  group('atomicidad visita + outbox (RD-04)', () {
    test('éxito: ambas filas se guardan juntas en una sola transacción', () async {
      await db.saveVisitWithOutboxOp(
        visit: sampleVisit(id: 'visit-1'),
        outboxOp: sampleOutboxOp(opUuid: 'op-1', entityId: 'visit-1'),
      );

      expect(await db.select(db.visits).get(), hasLength(1));
      expect(await db.select(db.outboxOps).get(), hasLength(1));
    });

    test(
      'un fallo a mitad de la transacción no deja huérfanos: ni la visita '
      'ni el outbox sobreviven',
      () async {
        await expectLater(
          db.transaction(() async {
            // Simula "guardar visita + encolar operación" pero forzando la
            // excepción justo entre las dos escrituras (la técnica que el
            // brief del Paso 11 sugiere explícitamente: "forzar excepción
            // tras el primer insert").
            await db.into(db.visits).insert(sampleVisit(id: 'visit-huerfana'));
            throw Exception('fallo simulado entre las dos escrituras');
          }),
          throwsException,
        );

        final storedVisits = await db.select(db.visits).get();
        final storedOps = await db.select(db.outboxOps).get();

        expect(
          storedVisits,
          isEmpty,
          reason: 'la visita no debe sobrevivir si el outbox nunca se escribió: '
              'sería una fila de negocio sin su operación de sync, exactamente '
              'la divergencia que ADR-002 dice que la transacción única evita',
        );
        expect(storedOps, isEmpty);
      },
    );
  });
}
