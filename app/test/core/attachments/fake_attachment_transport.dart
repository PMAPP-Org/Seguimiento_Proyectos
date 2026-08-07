// Fake de `AttachmentTransport` — mismo patrón que `FakeSyncTransport`
// (`test/core/sync/fake_sync_transport.dart`): cola de respuestas
// programables, sin red real.
import 'package:visitacampo/core/attachments/attachment_result.dart';
import 'package:visitacampo/core/attachments/attachment_transport.dart';

class FakeAttachmentTransport implements AttachmentTransport {
  final List<AttachmentResult<PresignData>> presignResponses = [];
  final List<AttachmentResult<void>> uploadResponses = [];
  final List<AttachmentResult<void>> commitResponses = [];

  final List<String> presignedShas = [];
  final List<String> committedShas = [];

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
    required List<int> bytes,
  }) async {
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
