// Base de datos local (Paso 11, ADR-002): SQLite vía Drift + SQLCipher,
// modo WAL, `synchronous=NORMAL`, un único executor de escritura.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:meta/meta.dart';

import 'tables.dart';

part 'database.g.dart';

/// **Escritor único (RD-04, corrige H-04)**: QField desactivaba su
/// protección de concurrencia con un `#if 0` — la app terminaba con dos
/// rutas de código escribiendo la misma BD sin serializar entre sí. La
/// mitigación aquí no es solo disciplina: `AppDatabase.open()` lanza si se
/// llama una segunda vez en el mismo proceso, así que **no puede existir**
/// una segunda conexión de escritura al mismo archivo por error de
/// integración. Cualquier repositorio que necesite la BD recibe esta misma
/// instancia (inyectada vía Riverpod desde el Paso 22 en adelante) — nunca
/// construye la suya propia.
@DriftDatabase(tables: [Visits, OutboxOps, AttachmentQueue, SyncCursor])
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.executor);

  static bool _instanceOpened = false;

  /// La única forma válida de abrir la BD real de la app. `executor` ya
  /// debe tener la clave de cifrado fijada (`createEncryptedExecutor`) —
  /// esta clase no sabe nada de SQLCipher, solo aplica la regla de "una
  /// sola instancia por proceso".
  factory AppDatabase.open(QueryExecutor executor) {
    if (_instanceOpened) {
      throw StateError(
        'AppDatabase ya tiene una instancia abierta en este proceso. '
        'RD-04 (doc 08 ADR-002) exige un único executor de escritura: '
        'una segunda instancia sobre el mismo archivo reintroduciría '
        'exactamente la clase de bug de concurrencia que QField tenía '
        'desactivada con un `#if 0` (hallazgo H-04). Reutiliza la '
        'instancia inyectada en vez de crear una nueva.',
      );
    }
    _instanceOpened = true;
    return AppDatabase._(executor);
  }

  /// Bypasea la guarda de instancia única — **solo para tests**, donde cada
  /// caso necesita su propia BD aislada (típicamente en memoria). Nunca usar
  /// en código de la app.
  @visibleForTesting
  factory AppDatabase.forTesting(QueryExecutor executor) => AppDatabase._(executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    // v1 → v2 (Paso 12): añade `sync_cursor` y `outbox_op.error_message`.
    // Aditiva, no destructiva — ninguna columna existente cambia de tipo ni
    // se elimina, así que los datos de un usuario que ya tenía la app
    // instalada en v1 sobreviven intactos. Regla operativa del Paso 11
    // cumplida: el test hermano de esta migración vive en
    // `test/data/local/migration_test.dart`.
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(syncCursor);
        await migrator.addColumn(outboxOps, outboxOps.errorMessage);
      }
    },
  );

  /// `null`: el dispositivo nunca hizo un pull/bootstrap exitoso todavía —
  /// `SyncEngine.pull()` lo trata como "usa `CURSOR_ZERO`" (equivalente a
  /// pedir todo desde el principio).
  Future<String?> readCursor() async {
    final row = await (select(syncCursor)..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.cursor;
  }

  Future<void> writeCursor(String cursor, {required DateTime now}) {
    return into(
      syncCursor,
    ).insertOnConflictUpdate(SyncCursorCompanion.insert(cursor: cursor, updatedAt: now));
  }

  /// El outbox es una tabla más del mismo esquema (ADR-002): "guardar
  /// visita + encolar operación" es una única transacción SQLite, no dos
  /// pasos con riesgo de divergencia si el proceso muere entre medias.
  /// `test/data/local/database_test.dart` verifica la atomicidad real
  /// forzando un fallo a mitad de una transacción equivalente.
  Future<void> saveVisitWithOutboxOp({
    required VisitsCompanion visit,
    required OutboxOpsCompanion outboxOp,
  }) {
    return transaction(() async {
      await into(visits).insertOnConflictUpdate(visit);
      await into(outboxOps).insertOnConflictUpdate(outboxOp);
    });
  }
}

/// El executor de la BD real de la app: SQLCipher (vía el hook `source:
/// sqlcipher` de `pubspec.yaml` — `sqlcipher_flutter_libs` está
/// descontinuado desde `sqlite3` v3.x) + modo WAL + `synchronous=NORMAL`.
///
/// **Orden de las pragmas, no es arbitrario**: `PRAGMA key` tiene que ir
/// primero — es lo que le dice a SQLCipher cómo descifrar el archivo, y
/// ninguna otra sentencia (ni siquiera leer el `journal_mode` actual) puede
/// ejecutarse antes sin fallar contra un archivo cifrado ya existente.
///
/// **Por qué interpolar `encryptionKey` directamente en el SQL es seguro
/// aquí y no en ningún otro sitio del código**: SQLite no permite
/// parametrizar el valor de un `PRAGMA` (no es una sentencia DML), así que
/// la alternativa sería escribir un escapador de comillas a mano — más
/// superficie de bug que la que resuelve. Es seguro porque `encryptionKey`
/// **nunca** viene de fuera del dispositivo: la genera
/// `EncryptionKeyStore` con un alfabeto base64url que no contiene comillas
/// ni backslash. Si esta función alguna vez recibe una clave de otro
/// origen, esa garantía deja de sostenerse y hay que revisar esto primero.
QueryExecutor createEncryptedExecutor({required File file, required String encryptionKey}) {
  return NativeDatabase.createInBackground(
    file,
    setup: (rawDb) {
      rawDb.execute("PRAGMA key = '$encryptionKey';");
      rawDb.execute('PRAGMA journal_mode=WAL;');
      rawDb.execute('PRAGMA synchronous=NORMAL;');
    },
  );
}
