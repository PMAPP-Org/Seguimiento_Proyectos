// `AttachmentResult<T>`/`AttachmentError` — mismo patrón que
// `AuthResult`/`SyncError` (Tarea 7 del plan de despliegue del demo):
// ninguna llamada a `/v1/attachments/*` produce una excepción no capturada.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment_result.freezed.dart';

@freezed
sealed class AttachmentResult<T> with _$AttachmentResult<T> {
  const factory AttachmentResult.ok(T value) = AttachmentOk<T>;
  const factory AttachmentResult.err(AttachmentError error) = AttachmentErr<T>;
}

extension AttachmentResultIsOk<T> on AttachmentResult<T> {
  bool get isOk => this is AttachmentOk<T>;
}

@freezed
sealed class AttachmentError with _$AttachmentError {
  const factory AttachmentError.network(String message) = AttachmentNetworkError;
  const factory AttachmentError.unexpectedStatus(int statusCode, String body) =
      AttachmentUnexpectedStatus;
  const factory AttachmentError.malformedResponse(String details) = AttachmentMalformedResponse;
}
