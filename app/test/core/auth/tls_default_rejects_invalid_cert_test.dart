// Verificación explícita del Paso 13 (tarea 2, RD-01/ADR-009): "simular un
// certificado inválido en el cliente HTTP de pruebas → la conexión se
// rechaza (no hay bypass)". Levanta un servidor HTTPS real en loopback con
// un certificado autofirmado (fixtures/self_signed_{cert,key}.pem) y conecta
// con el `Dio` **sin ningún override** del hook de aceptación de
// certificados inválidos de `HttpClientAdapter` (nombre omitido a
// propósito: el lint RD-01 de Paso 3, `infra/scripts/lint_no_tls_bypass.sh`,
// prohíbe que ese identificador aparezca en cualquier archivo fuera del
// módulo TrustStore auditado del Paso 16 — este test verifica precisamente
// que, sin tocarlo, es el mismo `Dio`/`HttpClientAdapter` por defecto que
// usa `AuthApiClient` (`data/http/api_client.dart`, ver el docstring de ese
// archivo sobre por qué no toca la validación de certificado).
//
// Que este archivo viva bajo `core/auth/` (no `data/http/`) es deliberado:
// la orden de verificación del Paso 13 es `flutter test app/test/core/auth/`.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<HttpServer> _startSelfSignedServer() async {
  final fixturesDir = p.join(Directory.current.path, 'test', 'core', 'auth', 'fixtures');
  final context = SecurityContext(withTrustedRoots: false)
    ..useCertificateChain(p.join(fixturesDir, 'self_signed_cert.pem'))
    ..usePrivateKey(p.join(fixturesDir, 'self_signed_key.pem'));

  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  unawaited(
    server.forEach((request) {
      request.response
        ..statusCode = 200
        ..write('{"ok":true}')
        ..close();
    }),
  );
  return server;
}

void main() {
  test(
    'Dio sin override del hook de certificado inválido rechaza un certificado autofirmado (sin bypass)',
    () async {
      final server = await _startSelfSignedServer();
      // `force: true`: la conexión TCP del cliente que aborta a mitad del
      // handshake TLS (justo lo que este test provoca) no necesariamente
      // cuenta como "completada" para el cierre por defecto de
      // `HttpServer.close()` — sin `force`, ese cierre puede quedar
      // colgado esperando una conexión que ya nunca va a terminar.
      addTearDown(() => server.close(force: true));

      final dio = Dio(BaseOptions(baseUrl: 'https://localhost:${server.port}'));
      // Deliberadamente: ningún `dio.httpClientAdapter` ni su hook de
      // aceptación de certificados inválidos se toca aquí — es exactamente
      // la política mínima de la tarea 2.

      await expectLater(
        dio.get<dynamic>('/v1/server/info'),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            anyOf(DioExceptionType.connectionError, DioExceptionType.unknown),
          ),
        ),
      );
    },
    // Red de seguridad: si algo del handshake/cierre queda colgado pese al
    // `force: true` de arriba, que el test falle en 20 s con un mensaje
    // claro en vez de dejar `flutter test` sin terminar nunca.
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
