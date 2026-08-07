// `PhotoCapture` — la mitad de cámara que `CaptureScreen` necesita (Tarea 6
// del plan de despliegue del demo). `sha256` se calcula aquí, en el
// dispositivo, porque es lo que el contrato de adjuntos exige como
// identidad del contenido (`attachments/schemas.py::Sha256Path`,
// `Blob.sha256` en el servidor) — la Tarea 7 lo usa tal cual en
// `presign`/`commit`, nunca lo recalcula.
import 'dart:io';

class CapturedPhoto {
  const CapturedPhoto({
    required this.file,
    required this.sha256,
    required this.sizeBytes,
    required this.mime,
  });

  final File file;
  final String sha256;
  final int sizeBytes;
  final String mime;
}

abstract class PhotoCapture {
  /// `null` si el usuario cancela la captura.
  Future<CapturedPhoto?> takePhoto();
}
