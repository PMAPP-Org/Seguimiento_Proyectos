// Implementación real de `PhotoCapture` sobre `image_picker`. Sin test
// unitario propio, mismo motivo que `GeolocatorLocationSource` (envoltorio
// delgado de un plugin de plataforma) — se prueba a través de un fake en
// `test/features/capture/capture_screen_test.dart`.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/capture/photo_capture.dart';

class ImagePickerPhotoCapture implements PhotoCapture {
  ImagePickerPhotoCapture({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<CapturedPhoto?> takePhoto() async {
    final xFile = await _picker.pickImage(source: ImageSource.camera);
    if (xFile == null) return null;

    final bytes = await xFile.readAsBytes();
    final digest = sha256.convert(bytes);
    return CapturedPhoto(
      file: File(xFile.path),
      sha256: digest.toString(),
      sizeBytes: bytes.length,
      // La cámara de `image_picker` siempre entrega JPEG en Android/iOS —
      // coincide con la allow-list del servidor (`core/models/base.py::
      // MimeType`, `attachments/schemas.py::Mime`).
      mime: 'image/jpeg',
    );
  }
}
