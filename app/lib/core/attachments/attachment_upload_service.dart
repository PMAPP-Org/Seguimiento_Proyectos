// `AttachmentUploadService` — orquesta presign→PUT→commit para cada fila
// `pending` de `AttachmentQueue` (Tarea 7 del plan de despliegue del demo).
// No crea ninguna fila `VisitAttachment` en el servidor (Decisión de diseño
// 6 del plan: `sync/payloads.py::WRITABLE_ENTITIES` solo acepta `visit`) —
// esto sube y confirma el **blob**, nada más.
import 'dart:io';

import 'package:drift/drift.dart';

import '../../data/local/database.dart';
import 'attachment_result.dart';
import 'attachment_transport.dart';

class AttachmentDrainReport {
  const AttachmentDrainReport({required this.uploaded, required this.failed});

  final int uploaded;
  final int failed;
}

class AttachmentUploadService {
  AttachmentUploadService({
    required this.db,
    required this.transport,
    Future<Uint8List> Function(String path)? readBytes,
  }) : _readBytes = readBytes ?? _defaultReadBytes;

  final AppDatabase db;
  final AttachmentTransport transport;
  final Future<Uint8List> Function(String path) _readBytes;

  // `File.readAsBytes()` ya devuelve `Future<Uint8List>` en tiempo de
  // ejecución (hallazgo Importante de la revisión final: la subida real
  // solo funcionaba porque este valor concreto es un `Uint8List`, no porque
  // el tipo lo garantizara en algún punto de la cadena — ver
  // `AttachmentTransport.upload` y `AttachmentApiClient.upload`, que ahora
  // declaran `Uint8List` explícito de punta a punta).
  static Future<Uint8List> _defaultReadBytes(String path) => File(path).readAsBytes();

  /// Filas que este drenaje intenta subir: `pending` (nunca se intentó, o
  /// quedó reencolada) y `failed` (fallo previo).
  ///
  /// **Hallazgo Importante de la revisión final** (el botón "Sincronizar" es
  /// el único mecanismo de reintento en este alcance: el reintento en
  /// segundo plano del Paso 18 está diferido): seleccionar solo `pending`
  /// dejaba una fila `failed` varada para siempre, porque ningún camino de
  /// este archivo la devolvía nunca a `pending`. Se incluye `failed` aquí en
  /// vez de resetearla a `pending` antes de seleccionar porque es
  /// equivalente y más simple: esta lista ya es exactamente "lo que hay que
  /// intentar subir ahora".
  static const _statesToDrain = ['pending', 'failed'];

  Future<AttachmentDrainReport> drainPending() async {
    final pending =
        await (db.select(db.attachmentQueue)..where((t) => t.state.isIn(_statesToDrain))).get();

    var uploaded = 0;
    var failed = 0;
    for (final row in pending) {
      final ok = await _drainOne(row);
      if (ok) {
        uploaded++;
      } else {
        failed++;
      }
    }
    return AttachmentDrainReport(uploaded: uploaded, failed: failed);
  }

  Future<bool> _drainOne(AttachmentQueueData row) async {
    final Uint8List bytes;
    try {
      bytes = await _readBytes(row.localPath);
    } on Object {
      // Archivo local ausente/ilegible (borrado, permiso revocado, disco
      // lleno, etc.): mismo tratamiento defensivo que un fallo de red —
      // se marca failed y se sigue con el resto del lote (RD-02/RD-03).
      return _markFailed(row.sha256);
    }
    final presignResult = await transport.presign(
      sha256: row.sha256,
      size: bytes.length,
      mime: 'image/jpeg',
    );

    return presignResult.when(
      ok: (presign) async {
        if (!presign.alreadyPresent) {
          final uploadUrl = presign.uploadUrl;
          if (uploadUrl == null) {
            return _markFailed(row.sha256);
          }
          final uploadResult = await transport.upload(
            uploadUrl: uploadUrl,
            headers: presign.requiredHeaders ?? const {},
            bytes: bytes,
          );
          final uploadOk = uploadResult.isOk;
          if (!uploadOk) {
            return _markFailed(row.sha256);
          }
        }
        final commitResult = await transport.commit(
          sha256: row.sha256,
          size: bytes.length,
          mime: 'image/jpeg',
        );
        return commitResult.isOk ? _markUploaded(row.sha256) : _markFailed(row.sha256);
      },
      err: (_) => _markFailed(row.sha256),
    );
  }

  Future<bool> _markUploaded(String sha256) async {
    await (db.update(db.attachmentQueue)..where((t) => t.sha256.equals(sha256))).write(
      const AttachmentQueueCompanion(state: Value('uploaded')),
    );
    return true;
  }

  Future<bool> _markFailed(String sha256) async {
    await (db.update(db.attachmentQueue)..where((t) => t.sha256.equals(sha256))).write(
      const AttachmentQueueCompanion(state: Value('failed')),
    );
    return false;
  }
}
