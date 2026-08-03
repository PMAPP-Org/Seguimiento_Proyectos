// `TokenStore` en memoria para tests — `SecureTokenStore` real necesita el
// method channel de `flutter_secure_storage`, que no existe en `flutter test`
// sin un binding de plataforma. Este fake permite verificar directamente
// "login exitoso guarda tokens" / "login fallido no persiste nada"
// (verificación explícita del Paso 13) sin mockear un plugin nativo.
import 'package:visitacampo/core/auth/token_store.dart';

class FakeTokenStore implements TokenStore {
  final Map<String, String> _byDeviceId = {};

  @override
  Future<void> saveRefreshToken(String deviceId, String refreshToken) async {
    _byDeviceId[deviceId] = refreshToken;
  }

  @override
  Future<String?> readRefreshToken(String deviceId) async => _byDeviceId[deviceId];

  @override
  Future<void> clearRefreshToken(String deviceId) async {
    _byDeviceId.remove(deviceId);
  }

  bool get isEmpty => _byDeviceId.isEmpty;
}
