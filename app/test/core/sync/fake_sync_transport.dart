// Fake de `SyncTransport` para los tests del Paso 12 — "dominio puro... sin
// emulador" (doc 08 §8) significa que el protocolo se prueba entero sin
// conexión real. Cada método es programable con una cola de respuestas, para
// poder ensayar network→éxito, éxito→network (recuperación), etc.
import 'package:visitacampo/core/sync/result.dart';
import 'package:visitacampo/core/sync/sync_transport.dart';

class FakeSyncTransport implements SyncTransport {
  final List<Result<PushResponse>> pushResponses = [];
  final List<Result<PullResponse>> pullResponses = [];
  final List<Result<BootstrapResponse>> bootstrapResponses = [];

  final List<PushRequestBody> pushCalls = [];
  final List<({String cursor, int? limit})> pullCalls = [];
  int bootstrapCallCount = 0;

  @override
  Future<Result<PushResponse>> push(PushRequestBody body) async {
    pushCalls.add(body);
    if (pushResponses.isEmpty) {
      throw StateError('FakeSyncTransport.push() sin respuesta programada.');
    }
    return pushResponses.removeAt(0);
  }

  @override
  Future<Result<PullResponse>> pull({required String cursor, int? limit}) async {
    pullCalls.add((cursor: cursor, limit: limit));
    if (pullResponses.isEmpty) {
      throw StateError('FakeSyncTransport.pull() sin respuesta programada.');
    }
    return pullResponses.removeAt(0);
  }

  @override
  Future<Result<BootstrapResponse>> bootstrap() async {
    bootstrapCallCount++;
    if (bootstrapResponses.isEmpty) {
      throw StateError('FakeSyncTransport.bootstrap() sin respuesta programada.');
    }
    return bootstrapResponses.removeAt(0);
  }
}
