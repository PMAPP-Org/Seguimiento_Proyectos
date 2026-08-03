// Fake de `AuthTransport` — mismo patrón que `FakeSyncTransport`
// (`test/core/sync/fake_sync_transport.dart`, Paso 12): cada método se
// programa con una cola de respuestas, para ensayar login/refresh
// éxito→fallo, fallo→éxito, etc. sin red real.
import 'package:visitacampo/core/auth/auth_models.dart';
import 'package:visitacampo/core/auth/auth_result.dart';
import 'package:visitacampo/core/auth/auth_transport.dart';

class FakeAuthTransport implements AuthTransport {
  final List<AuthResult<LoginResponse>> loginResponses = [];
  final List<AuthResult<TokenPair>> refreshResponses = [];
  final List<AuthResult<void>> logoutResponses = [];
  final List<AuthResult<ServerInfo>> serverInfoResponses = [];

  int loginCallCount = 0;
  int refreshCallCount = 0;
  int logoutCallCount = 0;
  int serverInfoCallCount = 0;

  final List<({String refreshToken, String deviceId})> refreshCalls = [];

  @override
  Future<AuthResult<LoginResponse>> login({
    required String username,
    required String password,
    required DeviceInfo deviceInfo,
  }) async {
    loginCallCount++;
    if (loginResponses.isEmpty) {
      throw StateError('FakeAuthTransport.login() sin respuesta programada.');
    }
    return loginResponses.removeAt(0);
  }

  @override
  Future<AuthResult<TokenPair>> refresh({required String refreshToken, required String deviceId}) async {
    refreshCallCount++;
    refreshCalls.add((refreshToken: refreshToken, deviceId: deviceId));
    if (refreshResponses.isEmpty) {
      throw StateError('FakeAuthTransport.refresh() sin respuesta programada.');
    }
    return refreshResponses.removeAt(0);
  }

  @override
  Future<AuthResult<void>> logout({required String accessToken, required String refreshToken}) async {
    logoutCallCount++;
    if (logoutResponses.isEmpty) {
      throw StateError('FakeAuthTransport.logout() sin respuesta programada.');
    }
    return logoutResponses.removeAt(0);
  }

  @override
  Future<AuthResult<ServerInfo>> serverInfo({required String accessToken}) async {
    serverInfoCallCount++;
    if (serverInfoResponses.isEmpty) {
      throw StateError('FakeAuthTransport.serverInfo() sin respuesta programada.');
    }
    return serverInfoResponses.removeAt(0);
  }
}
