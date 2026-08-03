// `AuthController` — dominio puro de sesión (tareas 3/4/5 del Paso 13):
// login/logout, refresh con single-flight (para que N requests concurrentes
// con 401 disparen **un** solo `POST /v1/auth/refresh`, tarea 4: "exactamente
// un intento de refresh, no un loop"), y negociación de `server_time`
// (tarea 5). No conoce Dio ni HTTP: habla con `AuthTransport` (interfaz),
// igual que `SyncEngine` (Paso 12) habla con `SyncTransport` — el mecanismo
// real de red (`AuthApiClient` + `AuthInterceptor`, `data/http/`) es
// intercambiable sin tocar esta clase.
import 'auth_models.dart';
import 'auth_result.dart';
import 'auth_state.dart';
import 'auth_transport.dart';
import 'token_store.dart';

class AuthController {
  AuthController({
    required this._transport,
    required this._tokenStore,
    required this.deviceId,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final AuthTransport _transport;
  final TokenStore _tokenStore;

  /// Público como en `SyncEngine.deviceId` (Paso 12) — es un identificador
  /// estable, no un secreto; lo que sí es privado es todo lo que autentica.
  final String deviceId;
  final DateTime Function() _now;

  AuthState _state = const AuthState.unauthenticated();
  AuthState get state => _state;

  /// Access token JWT en memoria — tarea 3 del Paso 13: **nunca** persistido
  /// (deuda técnica intencional de almacenamiento completa en Paso 16, ver
  /// `token_store.dart`).
  String? _accessToken;
  String? get accessToken => _accessToken;

  Future<bool>? _refreshInFlight;

  Future<AuthResult<UserProfile>> login({
    required String username,
    required String password,
    required DeviceInfo deviceInfo,
  }) async {
    final result = await _transport.login(username: username, password: password, deviceInfo: deviceInfo);
    return result.when(
      ok: (response) async {
        _accessToken = response.tokens.accessToken;
        await _tokenStore.saveRefreshToken(deviceId, response.tokens.refreshToken);
        _state = AuthState.authenticated(
          user: response.user,
          accessTokenExpiresAt: _now().add(Duration(seconds: response.tokens.expiresIn)),
        );
        return AuthResult<UserProfile>.ok(response.user);
      },
      // Login fallido: no se toca `_accessToken` ni `TokenStore` — nada que
      // "deshacer" porque nunca se llegó a persistir nada (verificación
      // explícita del Paso 13: "login fallido no persiste nada").
      err: (error) async => AuthResult<UserProfile>.err(error),
    );
  }

  /// Tarea 4, primera mitad: "al recibir 401, invalidar el access token".
  /// Separado de `refreshOnce()` para que el llamador (`AuthInterceptor`)
  /// pueda invalidar inmediatamente al ver el 401, antes de que el refresh
  /// (que puede tardar) termine.
  void invalidateAccessToken() {
    _accessToken = null;
  }

  /// Tarea 4, segunda mitad: intenta **un** refresh. Comparte el mismo
  /// `Future` entre llamadas concurrentes (varias requests en vuelo pueden
  /// recibir 401 a la vez) para que nunca se disparen dos
  /// `POST /v1/auth/refresh` simultáneos por la misma sesión — la ventana de
  /// gracia de 30 s del servidor (Paso 15) existe para reintentos
  /// legítimamente espaciados, no para que el propio cliente duplique la
  /// petición.
  Future<bool> refreshOnce() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _tokenStore.readRefreshToken(deviceId);
    if (refreshToken == null) {
      _state = const AuthState.disconnected();
      return false;
    }

    final result = await _transport.refresh(refreshToken: refreshToken, deviceId: deviceId);
    return result.when(
      ok: (pair) async {
        _accessToken = pair.accessToken;
        await _tokenStore.saveRefreshToken(deviceId, pair.refreshToken);
        final current = _state;
        // Si por algún motivo no había perfil de usuario en memoria (no
        // debería ocurrir: refrescar implica que hubo login antes en este
        // proceso, o el estado ya viene de un login previo), se deja el
        // estado como estaba — nunca se inventa un `UserProfile`.
        if (current case Authenticated(user: final user)) {
          _state = AuthState.authenticated(
            user: user,
            accessTokenExpiresAt: _now().add(Duration(seconds: pair.expiresIn)),
          );
        }
        return true;
      },
      // Tarea 4, "si también falla → Disconnected y solicitar re-login, sin
      // borrar la outbox local": este módulo no tiene ninguna referencia a
      // la outbox (`AppDatabase`/`OutboxOps`), así que no puede borrarla ni
      // por accidente — la garantía es de diseño, no de disciplina.
      err: (error) async {
        _accessToken = null;
        _state = const AuthState.disconnected();
        return false;
      },
    );
  }

  /// `POST /v1/auth/logout` (doc 08 ADR-008: "no borra la outbox local del
  /// cliente" — de nuevo, cierto por construcción). Si no hay sesión que
  /// cerrar en el servidor (sin refresh token o sin access token válido), se
  /// limpia igual el estado local: cerrar sesión en un dispositivo que ya
  /// no tiene nada que revocar no debe fallar.
  Future<void> logout() async {
    final refreshToken = await _tokenStore.readRefreshToken(deviceId);
    final token = _accessToken;
    if (refreshToken != null && token != null) {
      await _transport.logout(accessToken: token, refreshToken: refreshToken);
    }
    _accessToken = null;
    await _tokenStore.clearRefreshToken(deviceId);
    _state = const AuthState.unauthenticated();
  }

  /// Tarea 5: negocia `schema_version`/`server_time` contra
  /// `GET /v1/server/info`. Se llama tras el login (doc 08 §6) — si no hay
  /// access token todavía, es un error de uso del llamador, no un caso de
  /// red: se refleja como `unauthorized` en vez de un `assert`.
  Future<AuthResult<ServerInfo>> fetchServerInfo() {
    final token = _accessToken;
    if (token == null) {
      return Future.value(const AuthResult.err(AuthError.unauthorized()));
    }
    return _transport.serverInfo(accessToken: token);
  }
}
