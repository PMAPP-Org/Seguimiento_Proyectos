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
    Future<List<int>> Function(String path)? readBytes,
  }) : _readBytes = readBytes ?? _defaultReadBytes;

  final AppDatabase db;
  final AttachmentTransport transport;
  final Future<List<int>> Function(String path) _readBytes;

  static Future<List<int>> _defaultReadBytes(String path) => File(path).readAsBytes();

  Future<AttachmentDrainReport> drainPending() async {
    final pending =
        await (db.select(db.attachmentQueue)..where((t) => t.state.equals('pending'))).get();

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
    final List<int> bytes;
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
