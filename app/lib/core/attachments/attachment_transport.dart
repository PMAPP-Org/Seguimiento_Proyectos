// `AttachmentTransport` — la mitad de red que `AttachmentUploadService`
// necesita (Tarea 7 del plan de despliegue del demo). Implementada por
// `AttachmentApiClient` (Dio real, `data/http/attachment_api_client.dart`) y
// por `FakeAttachmentTransport` en los tests.
import 'attachment_result.dart';

class PresignData {
  const PresignData({required this.alreadyPresent, this.uploadUrl, this.requiredHeaders});

  final bool alreadyPresent;
  final String? uploadUrl;
  final Map<String, String>? requiredHeaders;
}

abstract class AttachmentTransport {
  /// `POST /v1/attachments/presign`. Sin `visit_id` (Decisión de diseño 11
  /// del plan): evita depender de que el `push` de la visita ya haya
  /// terminado en el servidor.
  Future<AttachmentResult<PresignData>> presign({
    required String sha256,
    required int size,
    required String mime,
  });

  /// `PUT` directo a `uploadUrl` (host del object storage, no de la API de
  /// VisitaCampo) con los `headers` que el servidor exigió al firmar.
  Future<AttachmentResult<void>> upload({
    required String uploadUrl,
    required Map<String, String> headers,
    required List<int> bytes,
  });

  /// `POST /v1/attachments/{sha256}/commit`.
  Future<AttachmentResult<void>> commit({
    required String sha256,
    required int size,
    required String mime,
  });
}
