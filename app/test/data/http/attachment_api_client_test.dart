// `AttachmentApiClient.upload()` — hallazgo Importante de la revisión final:
// `upload()` declaraba `bytes` como `List<int>` y lo pasaba directo a Dio.
// Dio solo envía binario crudo en `data:` cuando el valor es efectivamente un
// `Uint8List` en tiempo de ejecución; con cualquier otro `List<int>` cae en
// el transformer por defecto (pensado para JSON) y la subida se corrompe
// (bytes equivocados, checksum distinto al que el `commit` prefirmado
// espera). Esto pasaba desapercibido porque `File.readAsBytes()` devuelve un
// `Uint8List` por accidente de implementación, y el test anterior solo
// ejercía un `List<int>.filled(...)` sin pasar por un `HttpClientAdapter`
// real, así que nunca comprobaba qué le llegaba de verdad a Dio.
//
// Este test usa `FakeHttpClientAdapter` (mismo fake que
// `test/data/http/sync_api_client_test.dart` y `test/core/auth/
// api_client_test.dart`) para inspeccionar `RequestOptions.data` tal como lo
// vería el adapter real -- si `upload()` volviera a declarar/pasar un
// `List<int>` que no fuera `Uint8List` en tiempo de ejecución, la aserción de
// tipo de este test fallaría.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/attachments/attachment_result.dart';
import 'package:visitacampo/data/http/attachment_api_client.dart';

import '../../core/auth/fake_http_client_adapter.dart';

void main() {
  test('upload() envia los bytes a Dio como Uint8List, no como List<int> generico', () async {
    final adapter = FakeHttpClientAdapter(
      (options) => ResponseBody.fromString('', 200),
    );
    final uploadDio = Dio()..httpClientAdapter = adapter;
    final client = AttachmentApiClient(
      dio: Dio(BaseOptions(baseUrl: 'https://api.test')),
      accessTokenProvider: () => 'unused',
      uploadDio: uploadDio,
    );

    // Deliberadamente una lista que NO es un Uint8List en el sitio de la
    // llamada (una lista de enteros generada, como haría cualquier código
    // que no pasara por `File.readAsBytes()`): si `upload()` no reforzara el
    // tipo en el punto donde llama a Dio, `options.data` llegaría siendo
    // este mismo `List<int>` y la aserción de abajo fallaría.
    final bytes = Uint8List.fromList(List<int>.generate(16, (i) => i));

    final result = await client.upload(
      uploadUrl: 'https://blob.test/put',
      headers: const {'x-amz-meta-sha256': 'abc'},
      bytes: bytes,
    );

    expect(result.isOk, isTrue);
    expect(adapter.requests, hasLength(1));
    final sentData = adapter.requests.single.data;
    expect(sentData, isA<Uint8List>());
    expect(sentData, orderedEquals(bytes));
  });
}
