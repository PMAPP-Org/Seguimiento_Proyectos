// `AttachmentApiClient` — implementación Dio real de `AttachmentTransport`
// (Tarea 7 del plan de despliegue del demo). `upload()` usa un `Dio` **sin**
// baseUrl ni cabeceras de autorización: `uploadUrl` es una URL prefirmada de
// un host de object storage (Cloudflare R2/MinIO), que autentica por firma
// en la propia URL, no con el bearer token de la API de VisitaCampo — mismo
// motivo por el que `AuthInterceptor` no debe interceptar esta llamada.
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/attachments/attachment_result.dart';
import '../../core/attachments/attachment_transport.dart';

class AttachmentApiClient implements AttachmentTransport {
  // `uploadDio` es inyectable (por defecto `Dio()`, el mismo comportamiento
  // de siempre) solo para poder probar `upload()` con un
  // `FakeHttpClientAdapter` sin red real (mismo patrón que
  // `test/data/http/sync_api_client_test.dart`) -- sigue siendo, en
  // producción, un `Dio` propio sin baseUrl ni cabeceras de autorización,
  // nunca el `_dio` compartido con `AuthInterceptor` (ver el comentario de
  // arriba sobre por qué).
  AttachmentApiClient({
    required this._dio,
    required this._accessTokenProvider,
    Dio? uploadDio,
  }) : _uploadDio = uploadDio ?? Dio();

  final Dio _dio;
  final Dio _uploadDio;
  final String Function() _accessTokenProvider;

  Options get _authOptions =>
      Options(headers: {'Authorization': 'Bearer ${_accessTokenProvider()}'});

  @override
  Future<AttachmentResult<PresignData>> presign({
    required String sha256,
    required int size,
    required String mime,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/attachments/presign',
        data: {'sha256': sha256, 'size': size, 'mime': mime},
        options: _authOptions,
      );
      final body = response.data ?? const <String, dynamic>{};
      final requiredHeaders = body['required_headers'] as Map<String, dynamic>?;
      return AttachmentResult.ok(
        PresignData(
          alreadyPresent: body['already_present'] as bool? ?? false,
          uploadUrl: body['upload_url'] as String?,
          requiredHeaders: requiredHeaders?.map((key, value) => MapEntry(key, value as String)),
        ),
      );
    } on DioException catch (e) {
      return AttachmentResult.err(_mapError(e));
    }
  }

  @override
  Future<AttachmentResult<void>> upload({
    required String uploadUrl,
    required Map<String, String> headers,
    required Uint8List bytes,
  }) async {
    try {
      await _uploadDio.put<void>(
        uploadUrl,
        // `Uint8List.fromList` es una copia sin costo real cuando `bytes` ya
        // es un `Uint8List` (el caso común) y una red de seguridad si algún
        // día dejara de serlo: el tipo del parámetro ya lo garantiza en
        // compilación, pero Dio decide cómo serializar `data:` mirando el
        // tipo en **tiempo de ejecución**, así que la garantía se refuerza
        // en el propio punto donde Dio la consume (hallazgo Importante de la
        // revisión final — ver el docstring de `AttachmentTransport.upload`).
        data: Uint8List.fromList(bytes),
        options: Options(headers: headers),
      );
      return const AttachmentResult.ok(null);
    } on DioException catch (e) {
      return AttachmentResult.err(_mapError(e));
    }
  }

  @override
  Future<AttachmentResult<void>> commit({
    required String sha256,
    required int size,
    required String mime,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/v1/attachments/$sha256/commit',
        data: {'size': size, 'mime': mime},
        options: _authOptions,
      );
      return const AttachmentResult.ok(null);
    } on DioException catch (e) {
      return AttachmentResult.err(_mapError(e));
    }
  }

  AttachmentError _mapError(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) {
      return AttachmentError.network(e.message ?? e.type.name);
    }
    final body = e.response?.data;
    return AttachmentError.unexpectedStatus(status, body == null ? '' : body.toString());
  }
}
