// Esquema Drift del Paso 11 (ADR-002). Tres tablas, un solo archivo de BD:
// el outbox es una tabla más del mismo esquema, así que "guardar visita +
// encolar operación" es una única transacción SQLite (ver
// `database.dart::saveVisitWithOutboxOp`), no dos pasos con riesgo de
// divergencia si el proceso muere entre medias.
import 'package:drift/drift.dart';

/// Espejo local de `Visit` (contrato `server/openapi/v1.yaml`,
/// `server/visitacampo/core/models/visit.py`). No incluye `assignmentId`
/// todavía — `Assignment` llega al cliente en un paso posterior del track
/// móvil; añadirlo es una migración propia con su test N-1→N, no algo que
/// se cuele aquí por adelantado.
class Visits extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  IntColumn get version => integer()();

  /// `null`: creada localmente, el servidor todavía no le asignó
  /// `change_seq` (doc 08 §4.4 — ese número solo existe tras el push).
  IntColumn get changeSeq => integer().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get templateVersionId => text()();

  /// JSON serializado (`Map<String, dynamic>` codificado por el `SyncEngine`,
  /// Paso 12) — la propia tabla no interpreta las respuestas del formulario.
  TextColumn get answersJson => text()();
  RealColumn get lat => real().nullable()();
  RealColumn get lon => real().nullable()();
  RealColumn get accuracyM => real().nullable()();
  RealColumn get altitudeM => real().nullable()();
  DateTimeColumn get capturedAt => dateTime()();
  TextColumn get deviceId => text()();
  TextColumn get createdBy => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Operaciones pendientes de sincronizar (doc 08 §4.3). La máquina de
/// estados completa (`pending → inflight → applied/conflicted/rejected/
/// quarantine`) es dominio del Paso 12 — esta tabla solo persiste lo que esa
/// máquina necesita leer al arrancar la app, para que el outbox sobreviva un
/// cierre de la app a mitad de un drenaje.
class OutboxOps extends Table {
  /// UUIDv7 (Paso 12) — la idempotencia real del push depende de que este
  /// valor se genere una sola vez en el dispositivo, nunca en el servidor.
  TextColumn get opUuid => text()();

  /// Contrato `EntityType`: `visit` | `visit_attachment` | `assignment` |
  /// `form_template_version`. Texto y no un enum Drift a propósito: el
  /// contrato es la fuente de verdad de qué valores son válidos, no el
  /// esquema local — igual que el servidor (`sync/schemas.py::EntityType`).
  TextColumn get entity => text()();
  TextColumn get entityId => text()();

  /// `create` | `update` | `delete` (contrato `RawSyncOp.op_type`).
  TextColumn get opType => text()();

  /// `null` en `create` (doc 08: "el `create` del push envía `base_version:
  /// null`, nunca 0").
  IntColumn get baseVersion => integer().nullable()();

  /// JSON serializado del `payload` de la operación tal como viajará en
  /// `POST /v1/sync/push` (contrato `RawSyncOp.payload`).
  TextColumn get payloadJson => text()();

  /// El `message` de `OpErrorSchema` cuando el estado es `quarantine`
  /// (`OutboxOpState.quarantine.reason`) — persistido para que sobreviva un
  /// reinicio de la app; sin esto, el usuario perdería el motivo mostrado en
  /// la UI de conflictos (Paso 23) cada vez que cierra la app. Columna
  /// añadida en `schemaVersion` 2 junto con `sync_cursor` (`database.dart`).
  /// Nunca lleva `details` del error (RD-12: nunca el dato que falló).
  TextColumn get errorMessage => text().nullable()();

  /// Estado de la máquina de doc 08 §4.3, como texto (Paso 12 define el
  /// `sealed class OutboxOpState` que produce/consume estos valores).
  TextColumn get state => text()();

  /// Orden FIFO de drenaje: el `SyncEngine` (Paso 12) procesa el outbox en
  /// el orden en que el usuario generó las operaciones, no en orden
  /// arbitrario — importante porque una `update`/`delete` puede depender de
  /// que su `create` ya se haya aplicado.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {opUuid};
}

/// Adjuntos pendientes de subir (Paso 18). `sha256` es la misma clave que
/// `Blob.sha256` en el servidor (`core/models/visit.py`): el adjunto se
/// identifica por contenido, nunca por nombre de archivo — la mitigación de
/// RD-06 (path traversal) empieza aquí, no solo en el backend.
class AttachmentQueue extends Table {
  TextColumn get sha256 => text()();
  TextColumn get localPath => text()();

  /// `pending` | `uploading` | `uploaded` | `failed` — la máquina de subida
  /// en segundo plano (Paso 18) define las transiciones exactas.
  TextColumn get state => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sha256};
}

/// Cursor de pull persistido (Paso 12, `SyncEngine.pull()`). Fila única
/// (`id` siempre `0`, forzado por el `CHECK`) — no hay "cursor por
/// dispositivo" que rastrear porque esta tabla ya vive en la BD de un solo
/// dispositivo. Tabla añadida en `schemaVersion` 2 (`database.dart`): la
/// primera migración real desde el Paso 11, con su test N-1→N en
/// `test/data/local/migration_test.dart`.
class SyncCursor extends Table {
  // Sin CHECK SQL de "fila única": el único código que escribe esta tabla
  // es `AppDatabase.writeCursor()`, que siempre usa `id=0` — no hay una
  // ruta de escritura externa que pudiera violar el invariante.
  // `clientDefault` (no `.withDefault`) para que `id` no sea obligatorio en
  // `SyncCursorCompanion.insert(...)`.
  IntColumn get id => integer().clientDefault(() => 0)();
  TextColumn get cursor => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
