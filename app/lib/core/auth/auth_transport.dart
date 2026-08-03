// `AuthTransport` — la mitad de red que `AuthController` necesita, mismo rol
// que `SyncTransport` (`core/sync/sync_transport.dart`, Paso 12): una
// interfaz implementada por `AuthApiClient` (Dio real, `data/http/`) y por
// un fake en los tests, para que la máquina de estados de `AuthController`
// se pruebe entera sin red real ("dominio puro... sin emulador", doc 08 §8).
import 'auth_models.dart';
import 'auth_result.dart';

abstract class AuthTransport {
  /// `POST /v1/auth/login` — `security: []` en el contrato, no lleva token.
  Future<AuthResult<LoginResponse>> login({
    required String username,
    required String password,
    required DeviceInfo deviceInfo,
  });

  /// `POST /v1/auth/refresh` — `security: []`, autentica con el propio
  /// `refreshToken` opaco, no con un access token.
  Future<AuthResult<TokenPair>> refresh({required String refreshToken, required String deviceId});

  /// `POST /v1/auth/logout` — requiere `Authorization: Bearer <accessToken>`
  /// (hereda `bearerAuth`, `authn/api.py`). Siempre idempotente en el
  /// servidor (204 exista o no el refresh token).
  Future<AuthResult<void>> logout({required String accessToken, required String refreshToken});

  /// `GET /v1/server/info` — requiere `Authorization: Bearer <accessToken>`.
  Future<AuthResult<ServerInfo>> serverInfo({required String accessToken});
}
