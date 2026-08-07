// Envuelve la tabla `AttachmentQueue` (`data/local/tables.dart`, Paso 11:
// "Adjuntos pendientes de subir"). Nadie la escribía todavía — esta tarea
// (6, captura de una foto) es su primer escritor; la Tarea 7 (subida
// manual) es su primer lector.
import 'database.dart';

class AttachmentQueueRepository {
  const AttachmentQueueRepository(this._db);

  final AppDatabase _db;

  /// Encola un adjunto pendiente de subir. Idempotente por `sha256` (clave
  /// primaria de `AttachmentQueue`, igual que `Blob.sha256` en el servidor):
  /// el mismo contenido nunca se encola dos veces, aunque el usuario tome la
  /// "misma" foto en dos capturas distintas.
  Future<void> enqueue({
    required String sha256,
    required String localPath,
    required DateTime now,
  }) {
    return _db
        .into(_db.attachmentQueue)
        .insertOnConflictUpdate(
          AttachmentQueueCompanion.insert(
            sha256: sha256,
            localPath: localPath,
            state: 'pending',
            createdAt: now,
          ),
        );
  }
}
