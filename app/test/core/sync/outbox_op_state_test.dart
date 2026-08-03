// Máquina de estados del outbox (doc 08 §4.3), Paso 12 — pura, sin BD ni
// red: exactamente el tipo de test que el brief pide ("dominio puro").
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/sync/outbox_op_state.dart';

void main() {
  group('pending → inflight', () {
    test('markInflight() transiciona desde pending', () {
      const pending = OutboxOpState.pending();
      expect(markInflight(pending), const OutboxOpState.inflight());
    });

    test('markInflight() lanza si no viene de pending (bug del SyncEngine)', () {
      expect(
        () => markInflight(const OutboxOpState.inflight()),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('inflight → pending (backoff)', () {
    test('primer fallo: attempt pasa de 0 a 1', () {
      final next = markRetryAfterTransportFailure(
        const OutboxOpState.inflight(),
        DateTime.utc(2026, 1, 1, 0, 0, 5),
      );
      expect(next, isA<OutboxPending>());
      expect((next as OutboxPending).attempt, 1);
      expect(next.nextAttemptAt, DateTime.utc(2026, 1, 1, 0, 0, 5));
    });

    test('fallos sucesivos incrementan attempt sobre el valor anterior', () {
      final first = markRetryAfterTransportFailure(
        const OutboxOpState.inflight(),
        DateTime.utc(2026, 1, 1),
      );
      final second = markRetryAfterTransportFailure(
        markInflight(first as OutboxPending),
        DateTime.utc(2026, 1, 1, 0, 0, 10),
      );
      expect((second as OutboxPending).attempt, 2);
    });

    test('no es válido desde quarantine', () {
      expect(
        () => markRetryAfterTransportFailure(
          const OutboxOpState.quarantine(reason: 'x'),
          DateTime.utc(2026, 1, 1),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('rejected → quarantine (nunca se descarta en silencio)', () {
    test('markRejectedAndQuarantine() conserva el motivo', () {
      final state = markRejectedAndQuarantine('Payload inválido: lat fuera de rango.');
      expect(state, isA<OutboxQuarantine>());
      expect(
        (state as OutboxQuarantine).reason,
        'Payload inválido: lat fuera de rango.',
      );
    });
  });

  group('quarantine → pending (reintento explícito, Paso 23)', () {
    test('retryFromQuarantine() reinicia attempt/nextAttemptAt', () {
      final state = retryFromQuarantine(const OutboxOpState.quarantine(reason: 'x'));
      expect(state, const OutboxOpState.pending());
    });

    test('no es válido desde pending', () {
      expect(
        () => retryFromQuarantine(const OutboxOpState.pending()),
        throwsA(isA<StateError>()),
      );
    });
  });
}
