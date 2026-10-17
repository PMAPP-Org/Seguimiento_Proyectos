// Dónde se guarda el PNG de una firma antes de subirlo (Paso 22).
import 'dart:typed_data';

import 'package:meta/meta.dart';

@immutable
class StoredFile {
  const StoredFile({required this.path, required this.sha256});
  final String path;
  final String sha256;
}

abstract class SignatureStore {
  /// Guarda [png] en el almacenamiento privado de la app y devuelve su ruta y
  /// su `sha256` (la identidad del adjunto, ADR-007).
  Future<StoredFile> save(Uint8List png);
}
