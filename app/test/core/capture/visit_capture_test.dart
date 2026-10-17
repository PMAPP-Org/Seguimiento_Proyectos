// `VisitCapture.save` (Paso 22, tarea 5): una visita entera en una sola
// transacción local, con sus adjuntos, operaciones de outbox y cola de subida.
// Incluye la prueba preliminar del criterio de doc 08 §8 ("jornada sin red:
// ≥50 visitas con 10 fotos c/u sin degradación perceptible"); la de carga
// completa es del Paso 25.
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/capture/visit_capture.dart';
import 'package:visitacampo/core/forms/form_definition.dart';
import 'package:visitacampo/core/location/location_source.dart';
import 'package:visitacampo/core/sync/result.dart';
import 'package:visitacampo/core/sync/sync_engine.dart';
import 'package:visitacampo/core/sync/sync_transport.dart';
import 'package:visitacampo/data/local/database.dart';
import 'package:visitacampo/data/local/visit_status_repository.dart';

import '../sync/fake_sync_transport.dart';

const identity = CaptureIdentity(orgId: 'org-1', userId: 'user-1', deviceId: 'device-1');

/// Plantilla con foto y firma condicionadas a "¿hay planta?".
FormDefinition definition() =>
    (parseFormDefinition({
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
                  'label': {'es': 'Altura'},
                  'visible_if': {'op': 'eq', 'field': 'tiene_planta', 'value': true},
                },
                {
                  'key': 'foto_planta',
                  'type': 'photo',
                  'label': {'es': 'Foto de la planta'},
                  'visible_if': {'op': 'eq', 'field': 'tiene_planta', 'value': true},
                },
                {
                  'key': 'firma',
                  'type': 'signature',
                  'label': {'es': 'Firma'},
                },
              ],
            })
            as DefinitionOk)
        .definition;

PendingAttachment attachment(String id, {String role = 'foto', String? sha, String mime = 'image/jpeg'}) =>
    PendingAttachment(
      id: id,
      sha256: sha ?? crypto.sha256.convert(utf8.encode(id)).toString(),
      localPath: '/datos/$id',
      mime: mime,
      role: role,
      capturedAt: DateTime.utc(2026, 10, 17, 9),
    );

void main() {
  late AppDatabase db;
  late VisitCapture capture;
  var counter = 0;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    counter = 0;
    capture = VisitCapture(
      db: db,
      idGenerator: () => 'id-${(counter++).toString().padLeft(4, '0')}',
      clock: () => DateTime.utc(2026, 10, 17, 10),
    );
  });
  tearDown(() => db.close());

  test('guarda visita, adjuntos, outbox y cola de subida juntos', () async {
    final photo = attachment('a-foto');
    final signature = attachment('a-firma', role: 'firma', mime: 'image/png');
    final extra = attachment('a-extra');
    final visitId = await capture.save(
      identity: identity,
      templateVersionId: 'tv-1',
      definition: definition(),
      answers: {'tiene_planta': true, 'altura_cm': 120, 'foto_planta': photo.id, 'firma': signature.id},
      captured: {photo.id: photo, signature.id: signature},
      extraPhotos: [extra],
      fix: const LocationFix(lat: 4.6, lon: -74.08, accuracyM: 4.5, altitudeM: 2600),
    );

    final visit = await (db.select(db.visits)..where((t) => t.id.equals(visitId))).getSingle();
    expect(visit.lat, 4.6);
    expect(visit.accuracyM, 4.5);
    expect(jsonDecode(visit.answersJson), {
      'tiene_planta': true,
      'altura_cm': 120,
      'foto_planta': 'a-foto',
      'firma': 'a-firma',
    });

    final attachments = await (db.select(db.visitAttachments)..orderBy([(t) => OrderingTerm(expression: t.position)])).get();
    expect([for (final a in attachments) (a.id, a.role, a.position)], [
      ('a-foto', 'foto', 0),
      ('a-firma', 'firma', 1),
      ('a-extra', 'foto', 2),
    ]);

    final uploads = await db.select(db.attachmentQueue).get();
    expect({for (final u in uploads) u.sha256: u.mime}, {
      photo.sha256: 'image/jpeg',
      signature.sha256: 'image/png',
      extra.sha256: 'image/jpeg',
    });

    final ops = await db.select(db.outboxOps).get();
    expect(ops.map((o) => o.entity), ['visit', 'visit_attachment', 'visit_attachment', 'visit_attachment']);
    final payload = jsonDecode(ops[1].payloadJson) as Map<String, dynamic>;
    expect(payload, {
      'id': 'a-foto',
      'visit_id': visitId,
      'sha256': photo.sha256,
      'role': 'foto',
      'caption': null,
      'captured_at': '2026-10-17T09:00:00.000Z',
      'order': 0,
    });
  });

  test('solo viajan las respuestas visibles y los adjuntos que se referencian', () async {
    final hidden = attachment('a-oculta');
    final replaced = attachment('a-repetida');
    final signature = attachment('a-firma', role: 'firma', mime: 'image/png');
    await capture.save(
      identity: identity,
      templateVersionId: 'tv-1',
      definition: definition(),
      // "No hay planta": la altura y la foto quedan ocultas.
      answers: {'tiene_planta': false, 'altura_cm': 50, 'foto_planta': hidden.id, 'firma': signature.id},
      // `a-repetida` se capturó y se sustituyó antes de guardar: no se referencia.
      captured: {hidden.id: hidden, replaced.id: replaced, signature.id: signature},
    );

    final visit = await db.select(db.visits).getSingle();
    expect(jsonDecode(visit.answersJson), {'tiene_planta': false, 'firma': 'a-firma'});
    expect((await db.select(db.visitAttachments).get()).map((a) => a.id), ['a-firma']);
    expect((await db.select(db.attachmentQueue).get()).map((u) => u.sha256), [signature.sha256]);
  });

  test('atomicidad: si algo falla a mitad, no queda nada guardado', () async {
    // Un adjunto con el mismo id ya existe: su INSERT falla dentro de la
    // transacción, después de haber insertado la visita.
    await db
        .into(db.visitAttachments)
        .insert(
          VisitAttachmentsCompanion.insert(
            id: 'a-dup',
            orgId: 'org-1',
            visitId: 'otra',
            sha256: 'f' * 64,
            role: 'foto',
            capturedAt: DateTime.utc(2026),
            position: 0,
          ),
        );
    final dup = attachment('a-dup');

    await expectLater(
      capture.save(
        identity: identity,
        templateVersionId: 'tv-1',
        definition: definition(),
        answers: {'tiene_planta': true, 'foto_planta': dup.id},
        captured: {dup.id: dup},
      ),
      throwsA(isA<Object>()),
    );

    expect(await db.select(db.visits).get(), isEmpty, reason: 'ni la visita');
    expect(await db.select(db.outboxOps).get(), isEmpty, reason: 'ni sus operaciones');
    expect(await db.select(db.attachmentQueue).get(), isEmpty, reason: 'ni la cola de subida');
  });

  test('una foto ya subida en otra visita no se vuelve a encolar', () async {
    final shared = attachment('a-1', sha: 'e' * 64);
    await db
        .into(db.attachmentQueue)
        .insert(
          AttachmentQueueCompanion.insert(
            sha256: shared.sha256,
            localPath: '/datos/vieja',
            state: 'uploaded',
            createdAt: DateTime.utc(2026),
          ),
        );
    await capture.save(
      identity: identity,
      templateVersionId: 'tv-1',
      definition: definition(),
      answers: {'tiene_planta': true, 'foto_planta': shared.id},
      captured: {shared.id: shared},
    );
    final upload = await db.select(db.attachmentQueue).getSingle();
    expect(upload.state, 'uploaded');
    expect(upload.localPath, '/datos/vieja');
  });

  test('el push envía la visita antes que sus adjuntos aunque compartan createdAt', () async {
    final photos = [for (var i = 0; i < 5; i++) attachment('a-$i')];
    await capture.save(
      identity: identity,
      templateVersionId: 'tv-1',
      definition: definition(),
      answers: {'tiene_planta': true},
      captured: const {},
      extraPhotos: photos,
    );
    final transport = FakeSyncTransport();
    transport.pushResponses.add(const Result.err(SyncError.network('sin red')));
    await SyncEngine(db: db, transport: transport, deviceId: 'device-1').drainOutbox();

    final sent = transport.pushCalls.single.ops;
    expect(sent.first.entity, 'visit');
    expect(sent.skip(1).map((op) => op.payload['order']), [0, 1, 2, 3, 4]);
  });

  test('estado: pendiente → sincronizada con fotos por subir → todo subido', () async {
    final photo = attachment('a-1');
    final visitId = await capture.save(
      identity: identity,
      templateVersionId: 'tv-1',
      definition: definition(),
      answers: {'tiene_planta': true, 'foto_planta': photo.id},
      captured: {photo.id: photo},
    );
    final status = VisitStatusRepository(db);
    var summary = (await status.recentVisits(orgId: 'org-1')).single;
    expect((summary.id, summary.status, summary.attachments, summary.pendingUploads), (
      visitId,
      VisitSyncStatus.pending,
      1,
      1,
    ));

    // El servidor aplica las dos operaciones.
    final ops = await db.select(db.outboxOps).get();
    final transport = FakeSyncTransport()
      ..pushResponses.add(
        Result.ok(
          PushResponse(
            schemaVersion: 1,
            results: [for (final op in ops) PushOpOutcome(opUuid: op.opUuid, status: 'applied', serverVersion: 1)],
          ),
        ),
      );
    await SyncEngine(db: db, transport: transport, deviceId: 'device-1').drainOutbox();
    summary = (await status.recentVisits(orgId: 'org-1')).single;
    expect((summary.status, summary.pendingUploads), (VisitSyncStatus.synced, 1));

    await (db.update(db.attachmentQueue)).write(const AttachmentQueueCompanion(state: Value('uploaded')));
    summary = (await status.recentVisits(orgId: 'org-1')).single;
    expect(summary.pendingUploads, 0);
  });

  test('estado: una operación en cuarentena marca la visita como rechazada', () async {
    await capture.save(
      identity: identity,
      templateVersionId: 'tv-1',
      definition: definition(),
      answers: {'tiene_planta': true},
      captured: const {},
    );
    await db.update(db.outboxOps).write(const OutboxOpsCompanion(state: Value('quarantine')));
    expect((await VisitStatusRepository(db).recentVisits(orgId: 'org-1')).single.status, VisitSyncStatus.rejected);
  });

  test('prueba preliminar: 50 visitas × 10 fotos sin degradación', () async {
    final durations = <Duration>[];
    for (var v = 0; v < 50; v++) {
      final photos = [
        for (var p = 0; p < 10; p++) attachment('v$v-p$p', sha: (v * 10 + p).toRadixString(16).padLeft(64, '0')),
      ];
      final watch = Stopwatch()..start();
      await capture.save(
        identity: identity,
        templateVersionId: 'tv-1',
        definition: definition(),
        answers: {'tiene_planta': true, 'altura_cm': v},
        captured: const {},
        extraPhotos: photos,
      );
      durations.add(watch.elapsed);
    }

    expect(await db.select(db.visits).get(), hasLength(50));
    expect(await db.select(db.visitAttachments).get(), hasLength(500));
    expect(await db.select(db.attachmentQueue).get(), hasLength(500));
    expect(await db.select(db.outboxOps).get(), hasLength(550));

    double averageMs(Iterable<Duration> ds) => ds.map((d) => d.inMicroseconds).reduce((a, b) => a + b) / ds.length / 1000;
    final first = averageMs(durations.take(10));
    final last = averageMs(durations.skip(40));
    // "Sin degradación perceptible": guardar la visita 50 no cuesta
    // apreciablemente más que guardar la primera (holgura para el ruido del
    // runner de CI), y nunca más de lo que el agente notaría.
    expect(last, lessThan(first * 3 + 20), reason: 'primeras: ${first}ms, últimas: ${last}ms');
    expect(last, lessThan(250));

    final summaries = await VisitStatusRepository(db).recentVisits(orgId: 'org-1');
    expect(summaries, hasLength(50));
    expect(summaries.every((s) => s.attachments == 10 && s.pendingUploads == 10), isTrue);
  });
}
