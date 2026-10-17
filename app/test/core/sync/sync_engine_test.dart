// `SyncEngine` — Paso 12, los 4 casos obligatorios de doc 08 §8:
// idempotencia, backoff (reloj falso), conflicto, cursor expirado. Más el
// test de parseo estricto (RD-02/RD-03: nunca una excepción no capturada).
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/sync/result.dart';
import 'package:visitacampo/core/sync/sync_engine.dart';
import 'package:visitacampo/core/sync/sync_transport.dart';
import 'package:visitacampo/data/local/database.dart';
import 'package:visitacampo/data/local/form_template_repository.dart';

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
                serverRow: {'entity': 'visit', 'data': serverVisitRow(version: 2, lat: 9.9)},
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
              PushOpOutcome(opUuid: 'id-0', status: 'applied', serverRow: {'entity': 'visit', 'data': serverVisitRow()}),
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
              PushOpOutcome(opUuid: 'id-0', status: 'applied', serverRow: {'entity': 'visit', 'data': serverVisitRow()}),
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

  group('adjuntos de visita y server_row (Paso 22)', () {
    Map<String, dynamic> attachmentData({String? deletedAt}) => {
      'id': 'att-1',
      'org_id': 'org-1',
      'version': 1,
      'change_seq': 60,
      'deleted_at': deletedAt,
      'visit_id': 'visit-1',
      'sha256': 'ab' * 32,
      'role': 'foto',
      'caption': null,
      'captured_at': '2026-10-17T14:00:00Z',
      'order': 0,
    };

    Future<String> enqueueAttachmentOp() async {
      await db
          .into(db.outboxOps)
          .insert(
            OutboxOpsCompanion.insert(
              opUuid: 'op-att',
              entity: 'visit_attachment',
              entityId: 'att-1',
              opType: 'create',
              payloadJson: '{"id": "att-1"}',
              state: 'pending',
              createdAt: DateTime.utc(2026, 10, 17),
            ),
          );
      return 'op-att';
    }

    test('conflicto de un adjunto: se aplica su server_row y la op se borra', () async {
      final opUuid = await enqueueAttachmentOp();
      transport.pushResponses.add(
        Result.ok(
          PushResponse(
            schemaVersion: 1,
            results: [
              PushOpOutcome(
                opUuid: opUuid,
                status: 'conflict',
                serverVersion: 1,
                serverRow: {'entity': 'visit_attachment', 'data': attachmentData()},
              ),
            ],
          ),
        ),
      );
      final report = await buildEngine().drainOutbox();
      expect(report.conflicted, 1);
      expect(await db.select(db.outboxOps).get(), isEmpty);
      expect((await db.select(db.visitAttachments).getSingle()).sha256, 'ab' * 32);
    });

    test('un server_row que no es un EntityRecord va a cuarentena, no se pierde ni se atasca', () async {
      final opUuid = await enqueueAttachmentOp();
      transport.pushResponses.add(
        Result.ok(
          PushResponse(
            schemaVersion: 1,
            results: [
              // La forma que el cliente esperaba antes del Paso 22: `data` suelto.
              PushOpOutcome(opUuid: opUuid, status: 'conflict', serverRow: serverVisitRow()),
            ],
          ),
        ),
      );
      final report = await buildEngine().drainOutbox();
      expect(report.quarantined, 1);
      final op = await db.select(db.outboxOps).getSingle();
      expect(op.state, 'quarantine', reason: 'nunca queda en inflight');
    });

    test('el pull guarda los adjuntos y sus tombstones los quitan', () async {
      transport.pullResponses
        ..add(
          Result.ok(
            PullResponse(
              rows: [PullRow(entity: 'visit_attachment', data: attachmentData())],
              tombstones: [],
              nextCursor: 'c1:00000000000000000060',
              hasMore: false,
            ),
          ),
        )
        ..add(
          Result.ok(
            PullResponse(
              rows: [],
              tombstones: [
                PullTombstone(entity: 'visit_attachment', id: 'att-1', changeSeq: 61, deletedAt: DateTime.utc(2026, 10, 18)),
              ],
              nextCursor: 'c1:00000000000000000061',
              hasMore: false,
            ),
          ),
        );
      final engine = buildEngine();
      await engine.pull();
      expect((await db.select(db.visitAttachments).getSingle()).position, 0);
      await engine.pull();
      expect(await db.select(db.visitAttachments).get(), isEmpty);
    });
  });

  group('plantillas de formulario (Paso 21)', () {
    Map<String, dynamic> templateRow({required String id, required int versionNumber}) => {
      'id': id,
      'org_id': 'org-1',
      'version': 1,
      'change_seq': 50 + versionNumber,
      'deleted_at': null,
      'template_id': 'tpl-1',
      'name': 'Inspección',
      'version_number': versionNumber,
      'definition': {
        'fields': [
          {
            'key': 'campo_v$versionNumber',
            'type': 'text',
            'label': {'es': 'Campo'},
          },
        ],
      },
      'published_at': '2026-10-01T00:00:00Z',
    };

    String latestKey(TemplateLookup lookup) => switch (lookup) {
      TemplateReady(:final definition) => definition.fields.single.key,
      _ => fail('plantilla no lista: $lookup'),
    };

    test('el pull guarda las versiones y sus tombstones en la caché', () async {
      final engine = buildEngine();
      transport.pullResponses
        ..add(
          Result.ok(
            PullResponse(
              rows: [
                PullRow(entity: 'form_template_version', data: templateRow(id: 'v-1', versionNumber: 1)),
                PullRow(entity: 'form_template_version', data: templateRow(id: 'v-2', versionNumber: 2)),
                // Una fila rota no tumba el resto del pull.
                const PullRow(entity: 'form_template_version', data: {'id': 'roto'}),
              ],
              tombstones: [],
              nextCursor: 'c1:00000000000000000052',
              hasMore: false,
            ),
          ),
        )
        ..add(
          Result.ok(
            PullResponse(
              rows: [],
              tombstones: [
                PullTombstone(
                  entity: 'form_template_version',
                  id: 'v-2',
                  changeSeq: 53,
                  deletedAt: DateTime.utc(2026, 10, 2),
                ),
              ],
              nextCursor: 'c1:00000000000000000053',
              hasMore: false,
            ),
          ),
        );

      expect((await engine.pull()).isOk, isTrue);
      expect(latestKey(await engine.templates.latestForNewVisit(orgId: 'org-1', templateId: 'tpl-1')), 'campo_v2');

      expect((await engine.pull()).isOk, isTrue);
      expect(
        latestKey(await engine.templates.latestForNewVisit(orgId: 'org-1', templateId: 'tpl-1')),
        'campo_v1',
        reason: 'la v2 retirada deja de ofrecerse',
      );
      expect(await db.readCursor(), 'c1:00000000000000000053');
    });

    test('el bootstrap también llena la caché', () async {
      final engine = buildEngine();
      transport.pullResponses.add(const Result.err(SyncError.cursorExpired()));
      transport.bootstrapResponses.add(
        Result.ok(
          BootstrapResponse(
            cursor: 'c1:00000000000000000099',
            visits: const [],
            formTemplateVersions: [templateRow(id: 'v-1', versionNumber: 1)],
          ),
        ),
      );

      expect((await engine.pull()).isOk, isTrue);
      expect(latestKey(await engine.templates.latestForNewVisit(orgId: 'org-1', templateId: 'tpl-1')), 'campo_v1');
    });

    test('BootstrapResponse lee form_template_versions del contrato', () {
      final parsed = BootstrapResponse.fromJson({
        'cursor': 'c1:00000000000000000001',
        'visits': <dynamic>[],
        'form_template_versions': [templateRow(id: 'v-1', versionNumber: 1)],
      });
      expect(parsed.formTemplateVersions, hasLength(1));
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
