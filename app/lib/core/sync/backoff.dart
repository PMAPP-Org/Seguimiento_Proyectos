// Backoff exponencial + jitter (doc 08 §4.3, Paso 12 tarea 1: "inflight →
// pending: error de red/5xx/timeout, backoff exponencial + jitter").
// Función pura de `(attempt, ahora) -> próximo intento` — nada de `Timer`
// ni de dormir de verdad aquí, así que un test puede verificar la
// progresión exacta con un reloj y una fuente de aleatoriedad falsos
// (`test/core/sync/sync_engine_test.dart`), sin esperar segundos reales.
import 'dart:math';

abstract class BackoffPolicy {
  Duration delayFor(int attempt);
}

/// `base * 2^attempt`, con techo, más jitter aleatorio hasta `jitterMax`
/// para que reintentos de muchos dispositivos tras una caída del servidor no
/// lleguen todos en el mismo instante ("thundering herd").
class ExponentialBackoffWithJitter implements BackoffPolicy {
  const ExponentialBackoffWithJitter({
    this.base = const Duration(seconds: 1),
    this.max = const Duration(minutes: 5),
    this.jitterMax = const Duration(milliseconds: 500),
    Random Function()? randomFactory,
    // Sin formal inicializador: el parámetro tiene que ser público
    // (`randomFactory`, para que los tests puedan inyectar un generador
    // determinista) mientras el campo es privado — un nombre distinto en
    // cada lado es justo el caso que un formal inicializador no cubre.
    // ignore: prefer_initializing_formals
  }) : _randomFactory = randomFactory;

  final Duration base;
  final Duration max;
  final Duration jitterMax;
  final Random Function()? _randomFactory;

  @override
  Duration delayFor(int attempt) {
    // `attempt` puede llegar en 0 (primer fallo) — 2^0 = 1, la base tal
    // cual. Se acota `attempt` a 30 antes de la potencia para que un outbox
    // con cientos de fallos acumulados no desborde `Duration` calculando
    // `2^500`.
    final cappedAttempt = attempt.clamp(0, 30);
    final exponential = base * pow(2, cappedAttempt).toInt();
    final withCeiling = exponential > max ? max : exponential;

    final random = (_randomFactory ?? Random.secure)();
    final jitter = Duration(milliseconds: random.nextInt(jitterMax.inMilliseconds + 1));
    return withCeiling + jitter;
  }
}
