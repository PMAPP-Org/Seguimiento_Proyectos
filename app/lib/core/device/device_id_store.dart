// `DeviceIdStore` — identificador estable de este dispositivo, generado una
// vez y persistido en el keychain/keystore del sistema (mismo mecanismo que
// `EncryptionKeyStore`, `data/local/encryption_key_store.dart`, Paso 11).
// `AuthController.deviceId` y `SyncEngine.deviceId` (Pasos 12/13) esperan un
// identificador estable entre sesiones de la app; sin esto, cada arranque
// generaría un dispositivo nuevo en el servidor (`authn/services.py::
// _register_device`).
//
// `read`/`write` se inyectan (en vez de recibir un `FlutterSecureStorage`
// concreto) para poder probar la lógica de "generar solo la primera vez" sin
// el method channel del plugin, mismo motivo que documenta
// `test/core/auth/fake_token_store.dart` para `TokenStore`.
import 'dart:math';

class DeviceIdStore {
  DeviceIdStore({required this._read, required this._write, Random? random})
    : _random = random ?? Random.secure();

  static const _storageKey = 'visitacampo.device_id.v1';

  final Future<String?> Function({required String key}) _read;
  final Future<void> Function({required String key, required String value}) _write;
  final Random _random;

  Future<String> getOrCreateId() async {
    final existing = await _read(key: _storageKey);
    if (existing != null) {
      return existing;
    }
    final generated = _generateUuidV4();
    await _write(key: _storageKey, value: generated);
    return generated;
  }

  /// UUIDv4 sin dependencias externas: el paquete `uuid` (ya en
  /// `pubspec.yaml`) genera v4/v7, pero un identificador de dispositivo no
  /// necesita ser ordenable en el tiempo (a diferencia del `op_uuid` v7 del
  /// outbox) y evitar la dependencia aquí mantiene esta clase mínima.
  String _generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int start, int end) =>
        bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
