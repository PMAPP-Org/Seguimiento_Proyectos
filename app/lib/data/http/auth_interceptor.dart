// `AuthInterceptor` — flujo de refresco automático (tarea 4 del Paso 13):
// intercepta cualquier `401` de una request autenticada sobre el `Dio`
// compartido, invalida el access token, dispara **un** refresh
// (`AuthController.refreshOnce`, con single-flight) y reintenta la request
// original **una sola vez** con el token nuevo. Si el refresh falla, el
// controller ya quedó en `Disconnected` y este interceptor simplemente deja
// pasar el `401` original — no reintenta, no entra en loop.
//
// Excluye `/v1/auth/login` y `/v1/auth/refresh` a propósito: un `401` de
// login son credenciales inválidas (`AuthError.invalidCredentials`, nunca
// dispara refresh — no existe sesión que refrescar); un `401` de refresh es
// el propio intento de refresh fallando, y `AuthController._doRefresh` ya lo
// maneja sin pasar por aquí.
import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/auth/auth_controller.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.dio, required this.controller});

  /// Públicos como los campos equivalentes de `SyncEngine` (Paso 12): no son
  /// secretos, son las dos colaboraciones de las que depende este
  /// interceptor, fijadas una vez en la composición de la app.
  final Dio dio;
  final AuthController controller;

  static const _noRefreshPaths = {'/v1/auth/login', '/v1/auth/refresh'};

  /// Marca en `RequestOptions.extra` que esta request ya se reintentó una
  /// vez tras un refresh — la guarda que impide el loop si el token nuevo
  /// también resulta rechazado.
  static const _retriedFlag = 'visitacampo_auth_retried';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    unawaited(_handleError(err, handler));
  }

  Future<void> _handleError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final status = err.response?.statusCode;
    final alreadyRetried = options.extra[_retriedFlag] == true;

    if (status != 401 || _noRefreshPaths.contains(options.path) || alreadyRetried) {
      handler.next(err);
      return;
    }

    controller.invalidateAccessToken();
    final refreshed = await controller.refreshOnce();
    final newToken = controller.accessToken;
    if (!refreshed || newToken == null) {
      // `AuthController` ya transicionó a `Disconnected` — se propaga el
      // 401 original tal cual, sin reintentar.
      handler.next(err);
      return;
    }

    options.extra[_retriedFlag] = true;
    options.headers['Authorization'] = 'Bearer $newToken';
    try {
      final retryResponse = await dio.fetch<dynamic>(options);
      handler.resolve(retryResponse);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
