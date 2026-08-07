// `SyncApiClient` — Tarea 7 del plan de despliegue del demo. Primer cliente
// Dio real de `/v1/sync/*` (hasta ahora `SyncEngine`, Paso 12, solo se había
// probado contra `FakeSyncTransport`). Se prueba con `FakeHttpClientAdapter`
// (`test/core/auth/fake_http_client_adapter.dart`, ya construido en el Paso
// 13 para `AuthApiClient`/`AuthInterceptor`): recibe un `FakeHttpHandler`
// (`FutureOr<ResponseBody> Function(RequestOptions options)`) en el
// constructor y expone `requests: List<RequestOptions>` — no una cola de
// respuestas programable ni `lastRequestOptions` (esa forma pertenece a otro
// fake; esta es la real). `jsonResponseBody(data, statusCode)` construye la
// respuesta con el `Content-Type` que el transformer de Dio necesita.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/sync/result.dart';
import 'package:visitacampo/core/sync/sync_transport.dart';
import 'package:visitacampo/data/http/sync_api_client.dart';

import '../../core/auth/fake_http_client_adapter.dart';

void main() {
  test('push envia el lote y parsea la respuesta', () async {
    final adapter = FakeHttpClientAdapter(
      (options) => jsonResponseBody({
        'schema_version': 1,
        'server_time': '2026-08-06T12:00:00.000Z',
        'results': [
          {'op_uuid': 'a0000000-0000-7000-8000-000000000000', 'entity': 'visit', 'status': 'applied'},
        ],
      }, 200),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
    final client = SyncApiClient(dio: dio, accessTokenProvider: () => 'access-1');

    final result = await client.push(
      const PushRequestBody(
        schemaVersion: 1,
        deviceId: 'device-1',
        batchUuid: 'b0000000-0000-7000-8000-000000000000',
        ops: [],
      ),
    );

    expect(result.isOk, isTrue);
    final response = (result as Ok<PushResponse>).value;
    expect(response.results.single.status, 'applied');
    expect(adapter.requests.single.headers['Authorization'], 'Bearer access-1');
    expect(adapter.requests.single.path, '/v1/sync/push');
  });

  test('pull con 409 cursor_expired se traduce a SyncError.cursorExpired', () async {
    final adapter = FakeHttpClientAdapter(
      (options) => jsonResponseBody({'code': 'cursor_expired', 'message': 'expired'}, 409),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
    final client = SyncApiClient(dio: dio, accessTokenProvider: () => 'access-1');

    final result = await client.pull(cursor: 'c1:00000000000000000000');

    expect(result, isA<Err<PullResponse>>());
    expect((result as Err<PullResponse>).error, isA<CursorExpiredError>());
  });
}
