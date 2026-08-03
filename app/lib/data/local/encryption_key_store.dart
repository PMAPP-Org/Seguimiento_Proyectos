// Clave de cifrado de la BD local (ADR-002). Vive separada de
// `database.dart` porque tiene una sola responsabilidad —obtener o generar
// el secreto— y porque el almacenamiento seguro de tokens de sesión (Paso
// 13/16) reutilizará el mismo `FlutterSecureStorage`, no esta clase.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Obtiene (o genera, la primera vez) la clave de cifrado de SQLCipher.
///
/// La clave se genera **en el dispositivo**, nunca en el servidor ni
/// hardcodeada: 32 bytes de `Random.secure()` codificados en base64url. Se
/// persiste en el keychain/keystore del sistema operativo vía
/// `flutter_secure_storage` — el mismo mecanismo que ADR-002 exige para la
/// clave y que el Paso 13/16 extenderá para los tokens de sesión.
///
/// **Rotación**: fuera de alcance de este paso (doc 08 §4.2 la menciona como
/// parte del ciclo de vida completo, "rotación al re-loguear"). Aquí solo
/// existe la mitad "generar y persistir una vez".
class EncryptionKeyStore {
  const EncryptionKeyStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _storageKey = 'visitacampo.db_encryption_key.v1';

  /// Longitud en bytes de la clave generada — 256 bits, el tamaño estándar
  /// de clave de SQLCipher.
  static const _keyLengthBytes = 32;

  Future<String> getOrCreateKey() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null) {
      return existing;
    }

    final generated = _generateKey();
    await _storage.write(key: _storageKey, value: generated);
    return generated;
  }

  /// Base64url: alfabeto sin comillas ni backslash — se interpola
  /// directamente en `PRAGMA key = '...'` (`database.dart`), así que su
  /// alfabeto restringido no es una elección cosmética, es lo que hace esa
  /// interpolación segura sin necesitar un escapador de SQL para un `PRAGMA`
  /// (que SQLite no soporta parametrizar).
  String _generateKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(_keyLengthBytes, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
