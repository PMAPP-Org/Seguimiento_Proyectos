// Fake de `AttachmentTransport` — mismo patrón que `FakeSyncTransport`
// (`test/core/sync/fake_sync_transport.dart`): cola de respuestas
// programables, sin red real.
import 'dart:typed_data';

import 'package:visitacampo/core/attachments/attachment_result.dart';
import 'package:visitacampo/core/attachments/attachment_transport.dart';

class FakeAttachmentTransport implements AttachmentTransport {
  final List<AttachmentResult<PresignData>> presignResponses = [];
  final List<AttachmentResult<void>> uploadResponses = [];
  final List<AttachmentResult<void>> commitResponses = [];

  final List<String> presignedShas = [];
  final List<String> committedShas = [];

  /// Los `bytes` que recibió cada llamada a `upload()`, en orden — permite a
  /// un test comprobar que lo que llegó es realmente un `Uint8List` (hallazgo
  /// Importante de la revisión final: antes de este fix el tipo declarado no
  /// garantizaba nada en tiempo de ejecución).
  final List<Uint8List> uploadedBytes = [];

  @override
  Future<AttachmentResult<PresignData>> presign({
    required String sha256,
    required int size,
    required String mime,
  }) async {
    presignedShas.add(sha256);
    if (presignResponses.isEmpty) {
      throw StateError('FakeAttachmentTransport.presign() sin respuesta programada.');
    }
    return presignResponses.removeAt(0);
  }

  @override
  Future<AttachmentResult<void>> upload({
    required String uploadUrl,
    required Map<String, String> headers,
    required Uint8List bytes,
  }) async {
    uploadedBytes.add(bytes);
    if (uploadResponses.isEmpty) {
      throw StateError('FakeAttachmentTransport.upload() sin respuesta programada.');
    }
    return uploadResponses.removeAt(0);
  }

  @override
  Future<AttachmentResult<void>> commit({
    required String sha256,
    required int size,
    required String mime,
  }) async {
    committedShas.add(sha256);
    if (commitResponses.isEmpty) {
      throw StateError('FakeAttachmentTransport.commit() sin respuesta programada.');
    }
    return commitResponses.removeAt(0);
  }
}
