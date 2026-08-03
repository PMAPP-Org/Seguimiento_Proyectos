// `HttpClientAdapter` falso para los tests de `AuthApiClient`/`AuthInterceptor`
// (Paso 13) — evita abrir sockets reales; cada test programa qué responder
// según el path/orden de la request. Usa el punto de extensión oficial de
// Dio (`dio.httpClientAdapter =`), no un mock de `Dio` completo.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeHttpHandler = FutureOr<ResponseBody> Function(RequestOptions options);

class FakeHttpClientAdapter implements HttpClientAdapter {
  FakeHttpClientAdapter(this._handler);

  final FakeHttpHandler _handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Respuesta JSON con el `Content-Type` que el transformer de Dio necesita
/// para decodificarla automáticamente (`Transformer.isJsonMimeType`).
ResponseBody jsonResponseBody(Object? data, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}
