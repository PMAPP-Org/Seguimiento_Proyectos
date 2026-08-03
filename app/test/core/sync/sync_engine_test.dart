// `SyncEngine` — Paso 12, los 4 casos obligatorios de doc 08 §8:
// idempotencia, backoff (reloj falso), conflicto, cursor expirado. Más el
// test de parseo estricto (RD-02/RD-03: nunca una excepción no capturada).
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/sync/result.dart';
import 'package:visitacampo/core/sync/sync_engine.dart';
import 'package:visitacampo/core/sync/sync_transport.dart';
import 'package:visitacampo/data/local/database.dart';

import 'fake_sync_transport.dart';

void main() {
  late AppDatabase db;
  late FakeSyncTransport transport;
  DateTime fakeNow = DateTime.utc(2026, 1, 1);
  var uuidCounter = 0;

  SyncEngine buildEngine() => SyncEngine(
    db: db,
    transport: transport,
    deviceId: 'device-1',
    idGenerator: () => 'id-${uuidCounter++}',
    clock: () => fakeNow,
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    transport = FakeSyncTransport();
    fakeNow = DateTime.utc(2026, 1, 1);
    uuidCounter = 0;
  });

  tearDown(() => db.close());

  Map<String, dynamic> visitPayload({double lat = 4.6}) => {
    'id': 'visit-1',
    'template_version_id': 'template-1',
    'answers': {'altura_cm': 12},
    'captured_at': '2026-01-01T00:00:00.000Z',
    'device_id': 'device-1',
    'lat': lat,
  };

  Map<String, dynamic> serverVisitRow({int version = 1, int changeSeq = 42, double lat = 4.6}) => {
    'id': 'visit-1',
    'org_id': 'org-1',
    'version': version,
    'change_seq': changeSeq,
    'deleted_at': null,
    'assignment_id': null,
    'template_version_id': 'template-1',
    'answers': {'altura_cm': 12},
    'lat': lat,
    'lon': null,
    'accuracy_m': null,
    'altitude_m': null,
    'captured_at': '2026-01-01T00:00:00.000Z',
    'device_id': 'device-1',
    'created_by': 'user-1',
  };

  group('conflicto (inflight → conflicted → [*], sin merge de 3 vías)', () {
    test('server_row reemplaza la fila local; el outbox op se borra', () async {
      final engine = buildEngine();
      await engine.enqueueVisitOp(
        entityId: 'visit-1',
        opType: 'update',
        baseVersion: 1,
        payload: visitPayload(lat: 4.6),
      );

      transport.pushResponses.add(
        Result.ok(
          PushResponse(
            schemaVersion: 1,
            results: [
              PushOpOutcome(
                opUuid: 'id-0',
                status: 'conflict',
                serverRow: serverVisitRow(version: 2, lat: 9.9),
              ),
            ],
          ),
        ),
      );

      final report = await engine.drainOutbox();

      expect(report.conflicted, 1);
      expect(report.applied, 0);
      expect(await db.select(db.outboxOps).get(), isEmpty, reason: 'conflicted → [*]: sin rastro en el outbox');

      final visit = await (db.select(db.visits)..where((t) => t.id.equals('visit-1'))).getSingle();
      expect(visit.version, 2, reason: 'la fila local queda con la versión autoritativa del servidor');
      expect(visit.lat, 9.9, reason: 'server_row reemplaza la fila local entera, no un merge de campos');
    });
  });

  group('rejected → quarantine (nunca se descarta en silencio)', () {
    test('una op rechazada queda visible en quarantine con el motivo', () async {
      final engine = buildEngine();
      await engine.enqueueVisitOp(
        entityId: 'visit-1',
        opType: 'create',
        payload: visitPayload(lat: 999),
      );

      transport.pushResponses.add(
        Result.ok(
          PushResponse(
            schemaVersion: 1,
            results: [
              const PushOpOutcome(
                opUuid: 'id-0',
                status: 'rejected',
                error: PushOpError(code: 'validation_error', message: 'lat fuera de rango'),
              ),
            ],
          ),
        ),
      );

      final report = await engine.drainOutbox();
      expect(report.quarantined, 1);

      final op = await (db.select(db.outboxOps)..where((t) => t.opUuid.equals('id-0'))).getSingle();
      expect(op.state, 'quarantine');
      expect(op.errorMessage, 'lat fuera de rango');
    });
  });

  group('backoff exponencial (inflight → pending, reloj falso)', () {
    test('un fallo de red no reenvía antes de que venza el backoff', () async {
      final engine = buildEngine();
      await engine.enqueueVisitOp(
        entityId: 'visit-1',
        opType: 'create',
        payload: visitPayload(),
      );

      transport.pushResponses.add(const Result.err(SyncError.network('sin conexión')));
      final firstAttempt = await engine.drainOutbox();
      expect(firstAttempt.deferred, 1);
      expect(transport.pushCalls, hasLength(1));

      final afterFirstAttempt = await (db.select(
        db.outboxOps,
      )..where((t) => t.opUuid.equals('id-0'))).getSingle();
      expect(afterFirstAttempt.state, 'pending', reason: 'inflight → pending tras el fallo de transporte');

      // Todavía dentro de la ventana de backoff: drainOutbox() no debe
      // volver a llamar al transporte (no hay respuesta programada; si lo
      // intentara, FakeSyncTransport lanzaría).
      final tooSoon = await engine.drainOutbox();
      expect(tooSoon, DrainReport.empty);
      expect(transport.pushCalls, hasLength(1));

      // Avanza el reloj falso más allá de cualquier backoff razonable
      // (base 1s, techo 5min + jitter) y reintenta con éxito.
      fakeNow = fakeNow.add(const Duration(minutes: 10));
      transport.pushResponses.add(
        Result.ok(
          PushResponse(
            schemaVersion: 1,
            results: [
              PushOpOutcome(opUuid: 'id-0', status: 'applied', serverRow: serverVisitRow()),
            ],
          ),
        ),
      );
      final secondAttempt = await engine.drainOutbox();
      expect(secondAttempt.applied, 1);
      expect(transport.pushCalls, hasLength(2));

      final afterSecondAttempt = await db.select(db.outboxOps).getSingleOrNull();
      expect(afterSecondAttempt, isNull, reason: 'applied → [*]');
    });
  });

  group('idempotencia (reenviar/reprocesar no duplica estado local)', () {
    test('drainOutbox() tras un drenaje exitoso no reenvía ni duplica nada', () async {
      final engine = buildEngine();
      await engine.enqueueVisitOp(
        entityId: 'visit-1',
        opType: 'create',
        payload: visitPayload(),
      );

      transport.pushResponses.add(
        Result.ok(
          PushResponse(
            schemaVersion: 1,
            results: [
              PushOpOutcome(opUuid: 'id-0', status: 'applied', serverRow: serverVisitRow()),
            ],
          ),
        ),
      );
      final first = await engine.drainOutbox();
      expect(first.applied, 1);

      // Sin más respuestas programadas: si drainOutbox() reenviara la op ya
      // aplicada, FakeSyncTransport.push() lanzaría por falta de respuesta.
      // Que esto no pase demuestra que el outbox vacío no reprocesa nada.
      final second = await engine.drainOutbox();
      expect(second, DrainReport.empty);
      expect(transport.pushCalls, hasLength(1), reason: 'la op aplicada nunca se reenvía');

      final visits = await db.select(db.visits).get();
      expect(visits, hasLength(1), reason: 'ningún duplicado local');
    });
  });

  group('cursor expirado (409 → bootstrap automático, tarea 7)', () {
    test('pull() ante cursor_expired dispara un bootstrap y aplica su resultado', () async {
      final engine = buildEngine();
      transport.pullResponses.add(const Result.err(SyncError.cursorExpired()));
      transport.bootstrapResponses.add(
        Result.ok(BootstrapResponse(cursor: 'c1:00000000000000000099', visits: [serverVisitRow()])),
      );

      final result = await engine.pull();

      expect(result.isOk, isTrue, reason: 'cursor_expired se resuelve, nunca se propaga como error');
      expect(transport.bootstrapCallCount, 1);
      expect(await db.readCursor(), 'c1:00000000000000000099');
      expect(await db.select(db.visits).get(), hasLength(1));
    });

    test('pull() normal aplica filas y tombstones y guarda next_cursor', () async {
      final engine = buildEngine();
      transport.pullResponses.add(
        Result.ok(
          PullResponse(
            rows: [PullRow(entity: 'visit', data: serverVisitRow())],
            tombstones: [],
            nextCursor: 'c1:00000000000000000042',
            hasMore: false,
          ),
        ),
      );

      final result = await engine.pull();

      expect(result.isOk, isTrue);
      expect(await db.readCursor(), 'c1:00000000000000000042');
      expect(await db.select(db.visits).get(), hasLength(1));
      expect(transport.pullCalls.single.cursor, cursorZero);
    });
  });

  group('parseo estricto (RD-02/RD-03): nunca una excepción no capturada', () {
    test('parseJson() produce Err ante un campo requerido ausente', () {
      final result = parseJson(PushResponse.fromJson, <String, dynamic>{'schema_version': 1});
      expect(result, isA<Err<PushResponse>>());
    });

    test('parseJson() produce Ok con un cuerpo válido', () {
      final result = parseJson(PushResponse.fromJson, <String, dynamic>{
        'schema_version': 1,
        'results': <dynamic>[],
      });
      expect(result, isA<Ok<PushResponse>>());
    });
  });
}
