// `SyncApiClient` — implementación Dio real de `SyncTransport` (Tarea 7 del
// plan de despliegue del demo). Primer cliente real de `/v1/sync/*`; hasta
// ahora `SyncEngine` (Paso 12) solo se había ejercitado contra
// `FakeSyncTransport` en tests. Mismo patrón que `AuthApiClient`
// (`data/http/api_client.dart`, Paso 13): la cabecera `Authorization` se
// fija por request, no vía un interceptor global, porque no todos los
// clientes que comparten el `Dio` de la app necesitan token (el propio
// `AuthApiClient.login`/`refresh` no lo llevan).
import 'package:dio/dio.dart';

import '../../core/sync/result.dart';
import '../../core/sync/sync_transport.dart';

class SyncApiClient implements SyncTransport {
  SyncApiClient({required this._dio, required this._accessTokenProvider});

  final Dio _dio;
  final String Function() _accessTokenProvider;

  Options get _authOptions =>
      Options(headers: {'Authorization': 'Bearer ${_accessTokenProvider()}'});

  @override
  Future<Result<PushResponse>> push(PushRequestBody body) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/sync/push',
        data: body.toJson(),
        options: _authOptions,
      );
      return parseJson(PushResponse.fromJson, response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      return Result.err(_mapError(e));
    }
  }

  @override
  Future<Result<PullResponse>> pull({required String cursor, int? limit}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/sync/pull',
        queryParameters: {'cursor': cursor, 'limit': ?limit},
        options: _authOptions,
      );
      return parseJson(PullResponse.fromJson, response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      return Result.err(_mapError(e));
    }
  }

  @override
  Future<Result<BootstrapResponse>> bootstrap() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/sync/bootstrap',
        options: _authOptions,
      );
      return parseJson(BootstrapResponse.fromJson, response.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      return Result.err(_mapError(e));
    }
  }

  SyncError _mapError(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) {
      return SyncError.network(e.message ?? e.type.name);
    }
    final body = e.response?.data;
    if (status == 409 && body is Map<String, dynamic> && body['code'] == 'cursor_expired') {
      return const SyncError.cursorExpired();
    }
    return SyncError.unexpectedStatus(status, body == null ? '' : body.toString());
  }
}
