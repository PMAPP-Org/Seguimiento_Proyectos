// Máquina de estados del outbox (doc 08 §4.3), Paso 12 tarea 1.
//
// Diagrama exacto del doc: `pending → inflight` (el SyncEngine toma el
// lote) → `applied` | `conflicted` | `rejected` | (`inflight → pending` si
// falla el transporte, con backoff). `conflicted` y `applied` son
// **terminales para esta operación** (`conflicted → [*]`): la fila local se
// reemplaza por `server_row` o ya quedó aplicada, y el `SyncEngine` borra el
// `OutboxOp` de la tabla — no hay nada más que rastrear. `rejected` nunca es
// un estado de reposo: el `SyncEngine` lo lleva inmediatamente a
// `quarantine` (tarea 5: "rejected nunca se descarta en silencio"), que sí
// persiste hasta que el usuario actúa (`quarantine → pending` reintento, o
// `quarantine → [*]` descarte explícito, Paso 23).
//
// Solo tres variantes son estados de **reposo** que de verdad se persisten
// en `OutboxOps.state` (`data/local/tables.dart`): `pending`, `inflight` y
// `quarantine`. `applied`/`conflicted`/`rejected` son resultados de
// procesar la respuesta del push, no filas que sobrevivan en la tabla — por
// eso no tienen una variante de estado propia aquí, tienen una en
// `PushOpOutcome` (`sync_transport.dart`), que es lo que el `SyncEngine`
// consume para decidir la transición.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'outbox_op_state.freezed.dart';

@freezed
sealed class OutboxOpState with _$OutboxOpState {
  /// Esperando a ser incluida en el próximo lote de push. `nextAttemptAt`
  /// es `null` la primera vez; tras un fallo de transporte (`inflight →
  /// pending`) lleva la hora calculada por el backoff — el `SyncEngine` no
  /// intenta reenviar antes de esa hora aunque `drainOutbox()` se llame de
  /// nuevo.
  const factory OutboxOpState.pending({@Default(0) int attempt, DateTime? nextAttemptAt}) =
      OutboxPending;

  /// En vuelo: el `SyncEngine` ya la incluyó en un lote y espera la
  /// respuesta de `POST /v1/sync/push`. Si el proceso muere en este estado
  /// (la app se cierra a mitad), el arranque siguiente la trata como
  /// recuperable: vuelve a `pending` sin incrementar `attempt` — reenviar
  /// es seguro porque `op_uuid` hace el push idempotente en el servidor
  /// (Paso 8), así que no hay forma de saber si el servidor ya la aplicó sin
  /// preguntarle, y preguntarle otra vez (reenviando) es gratis.
  const factory OutboxOpState.inflight({@Default(0) int attempt}) = OutboxInflight;

  /// Terminal de verdad: requiere una acción explícita del usuario (Paso 23)
  /// o del propio `SyncEngine` (`retryQuarantined`). `reason` es el motivo
  /// legible por humanos, ya extraído del `OpErrorSchema` del servidor
  /// (contrato Paso 1) — nunca el payload que falló (RD-12: el cuerpo de
  /// error nunca hace eco del dato sensible).
  const factory OutboxOpState.quarantine({required String reason}) = OutboxQuarantine;
}

/// `pending → inflight`: el `SyncEngine` toma el lote (tarea 3). Pura por
/// diseño — no toca la BD, `SyncEngine` decide cuándo aplicarla.
OutboxOpState markInflight(OutboxOpState current) {
  if (current is! OutboxPending) {
    throw StateError(
      'markInflight() solo es válido desde pending; estado actual: $current. '
      'Esto sería un bug del SyncEngine, no una condición esperable en '
      'producción — drainOutbox() nunca debe seleccionar una op que no '
      'esté en pending.',
    );
  }
  return OutboxOpState.inflight(attempt: current.attempt);
}

/// `inflight → pending` con backoff (tarea 1: "error de red/5xx/timeout").
/// `attempt` sube en 1; `nextAttemptAt` lo calcula `BackoffPolicy`
/// (`backoff.dart`), no esta función — mantener el cálculo de tiempos fuera
/// de la máquina de estados es lo que permite testear cada uno con un reloj
/// falso por separado.
OutboxOpState markRetryAfterTransportFailure(OutboxOpState current, DateTime nextAttemptAt) {
  final previousAttempt = switch (current) {
    OutboxInflight(:final attempt) => attempt,
    OutboxPending(:final attempt) => attempt,
    OutboxQuarantine() => throw StateError(
      'markRetryAfterTransportFailure() no es válido desde quarantine; '
      'una op en quarantine no debe estar en un lote en vuelo.',
    ),
  };
  return OutboxOpState.pending(attempt: previousAttempt + 1, nextAttemptAt: nextAttemptAt);
}

/// `inflight → quarantine`, pasando por `rejected` conceptualmente (doc 08
/// §4.3: `rejected → quarantine` es inmediato — ver el docstring del
/// archivo). `reason` viene del `OpErrorSchema.message` del servidor.
OutboxOpState markRejectedAndQuarantine(String reason) => OutboxOpState.quarantine(reason: reason);

/// `quarantine → pending`: reintento explícito del usuario (Paso 23).
/// `attempt`/`nextAttemptAt` se reinician — un reintento manual no hereda el
/// backoff de los fallos automáticos anteriores.
OutboxOpState retryFromQuarantine(OutboxOpState current) {
  if (current is! OutboxQuarantine) {
    throw StateError('retryFromQuarantine() solo es válido desde quarantine; estado: $current.');
  }
  return const OutboxOpState.pending();
}
