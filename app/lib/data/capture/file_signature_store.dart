// `SignatureStore` real: el directorio de documentos de la app (privado, sin
// permisos de almacenamiento compartido). El nombre del archivo es su
// `sha256`: no sale de nada que escriba el usuario (RD-06).
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/capture/signature_store.dart';

class FileSignatureStore implements SignatureStore {
  const FileSignatureStore({this.baseDir});

  /// Directorio base (por defecto, el de documentos de la app). Para tests.
  final Future<Directory> Function()? baseDir;

  @override
  Future<StoredFile> save(Uint8List png) async {
    final digest = sha256.convert(png).toString();
    final base = await (baseDir ?? getApplicationDocumentsDirectory)();
    final dir = Directory(p.join(base.path, 'signatures'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '$digest.png'));
    await file.writeAsBytes(png, flush: true);
    return StoredFile(path: file.path, sha256: digest);
  }
}
