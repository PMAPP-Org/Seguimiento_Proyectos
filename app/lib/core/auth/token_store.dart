// `TokenStore` — abstrae "dónde se guarda el refresh token" (tarea 3 y
// estrategia de rollback del Paso 13). El access token JWT **no** pasa por
// aquí: vive en memoria del proceso (`AuthController._accessToken`), nunca
// persistido — es lo que la tarea 3 exige y lo que hace que un volcado del
// dispositivo no entregue una sesión activa (ADR-008, RD-09).
//
// **Deuda técnica intencional de esta implementación** (documentada, Paso 13
// tarea 3): `SecureTokenStore` usa `flutter_secure_storage` con sus flags de
// accesibilidad por defecto, sin todavía `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
// en iOS ni la integración con `TrustStore` (que no existe hasta el Paso
// 16). El **Paso 16** cierra esta deuda explícitamente (ver
// `visitacampo-construccion.md`, Paso 16). Que esto sea una interfaz desde
// ya es justo lo que permite ese reemplazo sin tocar `AuthController`.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TokenStore {
  /// Persiste el refresh token opaco del dispositivo (contrato
  /// `TokenPair.refresh_token`, patrón `selector.verifier`, ADR-008).
  Future<void> saveRefreshToken(String deviceId, String refreshToken);

  /// `null` si nunca hubo login o si se limpió (`clearRefreshToken`/logout).
  Future<String?> readRefreshToken(String deviceId);

  Future<void> clearRefreshToken(String deviceId);
}

/// Implementación real sobre el keychain/keystore del sistema — el mismo
/// `FlutterSecureStorage` que `EncryptionKeyStore` (Paso 11) usa para la
/// clave de SQLCipher, pero con su propio namespace de claves: son secretos
/// con ciclo de vida distinto (la clave de la BD sobrevive a un logout, el
/// refresh token no).
class SecureTokenStore implements TokenStore {
  const SecureTokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'visitacampo.refresh_token.v1.';

  String _keyFor(String deviceId) => '$_keyPrefix$deviceId';

  @override
  Future<void> saveRefreshToken(String deviceId, String refreshToken) {
    return _storage.write(key: _keyFor(deviceId), value: refreshToken);
  }

  @override
  Future<String?> readRefreshToken(String deviceId) {
    return _storage.read(key: _keyFor(deviceId));
  }

  @override
  Future<void> clearRefreshToken(String deviceId) {
    return _storage.delete(key: _keyFor(deviceId));
  }
}
