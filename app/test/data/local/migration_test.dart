// Regla operativa del Paso 11: ninguna migración destructiva sin un test de
// upgrade N-1→N con datos de ejemplo. Primera migración real: v1 (Paso 11)
// → v2 (Paso 12, añade `sync_cursor` y `outbox_ops.error_message`).
//
// Recrea el esquema v1 con SQL crudo (idéntico al que generaba
// `MigrationStrategy.onCreate` antes de este paso), inserta datos de
// ejemplo, y abre esa misma conexión con el `AppDatabase` real declarando
// `schemaVersion=2` — Drift detecta la diferencia de `user_version` y corre
// `onUpgrade`. Verifica que los datos v1 sobreviven intactos y que lo nuevo
// existe y es usable.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:visitacampo/data/local/database.dart';

void main() {
  test('v1 → v2: los datos existentes sobreviven, sync_cursor queda disponible', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    addTearDown(raw.close);

    // Esquema v1 (Paso 11) reconstruido a mano — deliberadamente independiente
    // de `tables.dart` actual: si este test importara las tablas de hoy para
    // "recrear v1", dejaría de probar una migración real y empezaría a
    // probar un no-op.
    raw.execute('''
      CREATE TABLE visits (
        id TEXT NOT NULL PRIMARY KEY,
        org_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        change_seq INTEGER NULL,
        deleted_at INTEGER NULL,
        template_version_id TEXT NOT NULL,
        answers_json TEXT NOT NULL,
        lat REAL NULL,
        lon REAL NULL,
        accuracy_m REAL NULL,
        altitude_m REAL NULL,
        captured_at INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        created_by TEXT NOT NULL
      );
      CREATE TABLE outbox_ops (
        op_uuid TEXT NOT NULL PRIMARY KEY,
        entity TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        op_type TEXT NOT NULL,
        base_version INTEGER NULL,
        payload_json TEXT NOT NULL,
        state TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE attachment_queue (
        sha256 TEXT NOT NULL PRIMARY KEY,
        local_path TEXT NOT NULL,
        state TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');
    raw.execute('PRAGMA user_version = 1;');

    raw.execute(
      'INSERT INTO visits (id, org_id, version, change_seq, template_version_id, answers_json, '
      'captured_at, device_id, created_by) VALUES '
      "('visit-1', 'org-1', 1, 42, 'template-1', '{}', 1767225600, 'device-1', 'user-1');",
    );
    raw.execute(
      "INSERT INTO outbox_ops (op_uuid, entity, entity_id, op_type, payload_json, state, created_at) "
      "VALUES ('op-1', 'visit', 'visit-1', 'create', '{}', 'pending', 1767225600);",
    );

    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Abrir ya dispara la migración (Drift la corre en el primer acceso).
    final visit = await (db.select(db.visits)..where((t) => t.id.equals('visit-1'))).getSingle();
    expect(visit.orgId, 'org-1', reason: 'los datos de v1 sobreviven la migración sin cambios');
    expect(visit.changeSeq, 42);

    final op = await (db.select(db.outboxOps)..where((t) => t.opUuid.equals('op-1'))).getSingle();
    expect(op.state, 'pending');
    expect(op.errorMessage, isNull, reason: 'columna nueva, sin valor previo: null por defecto');

    // La tabla nueva existe y es usable de inmediato.
    expect(await db.readCursor(), isNull);
    await db.writeCursor('c1:00000000000000000001', now: DateTime.utc(2026, 1, 1));
    expect(await db.readCursor(), 'c1:00000000000000000001');
  });

  test('v2 → v3: visitas, outbox y cursor sobreviven; la caché de plantillas queda disponible', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    addTearDown(raw.close);

    // Esquema v2 (Paso 12) a mano, por el mismo motivo que el test anterior.
    raw.execute('''
      CREATE TABLE visits (
        id TEXT NOT NULL PRIMARY KEY,
        org_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        change_seq INTEGER NULL,
        deleted_at INTEGER NULL,
        template_version_id TEXT NOT NULL,
        answers_json TEXT NOT NULL,
        lat REAL NULL,
        lon REAL NULL,
        accuracy_m REAL NULL,
        altitude_m REAL NULL,
        captured_at INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        created_by TEXT NOT NULL
      );
      CREATE TABLE outbox_ops (
        op_uuid TEXT NOT NULL PRIMARY KEY,
        entity TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        op_type TEXT NOT NULL,
        base_version INTEGER NULL,
        payload_json TEXT NOT NULL,
        state TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        error_message TEXT NULL
      );
      CREATE TABLE attachment_queue (
        sha256 TEXT NOT NULL PRIMARY KEY,
        local_path TEXT NOT NULL,
        state TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE sync_cursor (
        id INTEGER NOT NULL PRIMARY KEY,
        cursor TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    raw.execute('PRAGMA user_version = 2;');
    raw.execute(
      'INSERT INTO visits (id, org_id, version, change_seq, template_version_id, answers_json, '
      'captured_at, device_id, created_by) VALUES '
      "('visit-1', 'org-1', 3, 77, 'template-1', '{\"altura_cm\": 42}', 1767225600, 'device-1', 'user-1');",
    );
    raw.execute(
      "INSERT INTO outbox_ops (op_uuid, entity, entity_id, op_type, payload_json, state, created_at, error_message) "
      "VALUES ('op-1', 'visit', 'visit-1', 'update', '{}', 'quarantine', 1767225600, 'validation_error');",
    );
    raw.execute("INSERT INTO sync_cursor (id, cursor, updated_at) VALUES (0, 'c1:00000000000000000077', 1767225600);");

    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final visit = await (db.select(db.visits)..where((t) => t.id.equals('visit-1'))).getSingle();
    expect(visit.answersJson, '{"altura_cm": 42}');
    final op = await (db.select(db.outboxOps)..where((t) => t.opUuid.equals('op-1'))).getSingle();
    expect(op.errorMessage, 'validation_error');
    expect(await db.readCursor(), 'c1:00000000000000000077');

    await db
        .into(db.formTemplateVersions)
        .insert(
          FormTemplateVersionsCompanion.insert(
            id: 'v-1',
            orgId: 'org-1',
            templateId: 't-1',
            versionNumber: 1,
            definitionJson: '{"fields": []}',
            version: 1,
          ),
        );
    expect(await db.select(db.formTemplateVersions).get(), hasLength(1));
  });
}
