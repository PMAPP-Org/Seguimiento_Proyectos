// `DeviceIdStore` — identificador estable de este dispositivo (Tarea 5 del
// plan de despliegue del demo). Mismo patrón que `EncryptionKeyStore`
// (`data/local/encryption_key_store.dart`, Paso 11): genera una vez, persiste
// en el keychain/keystore del sistema, y en adelante siempre devuelve el
// mismo valor. Se prueba con un `FlutterSecureStorage` en memoria (fake),
// mismo criterio que `test/core/auth/fake_token_store.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/device/device_id_store.dart';

class _InMemorySecureStorage {
  final Map<String, String> _values = {};

  Future<String?> read({required String key}) async => _values[key];

  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}

void main() {
  group('DeviceIdStore.getOrCreateId', () {
    test('genera un id la primera vez y lo persiste', () async {
      final storage = _InMemorySecureStorage();
      final store = DeviceIdStore(read: storage.read, write: storage.write);

      final id = await store.getOrCreateId();

      expect(id, isNotEmpty);
      expect(await storage.read(key: 'visitacampo.device_id.v1'), id);
    });

    test('en llamadas posteriores devuelve siempre el mismo id', () async {
      final storage = _InMemorySecureStorage();
      final store = DeviceIdStore(read: storage.read, write: storage.write);

      final first = await store.getOrCreateId();
      final second = await store.getOrCreateId();

      expect(second, first);
    });
  });
}
