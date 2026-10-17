// DSL de visibilidad condicional en el cliente (Paso 21, tarea 3) — espejo de
// `server/visitacampo/forms/visibility.py` (Paso 20). Léase el docstring de
// ese archivo: aquí se repite solo lo imprescindible.
//
// **Una expresión es dato, nunca código** (ADR-012, RD-06, H-06): un objeto
// JSON con `op` de una allow-list cerrada. No hay texto que analizar, ni
// nombres que resolver, ni llamadas: `parseVisibility` construye un árbol de
// clases selladas y `evaluate` lo recorre con un `switch` exhaustivo. Un `op`
// fuera de la lista, una clave de más o un literal estructurado **no se
// evalúan nunca**: hacen que la plantilla entera se rechace al parsearla.
//
// La semántica de `evaluate` es **la misma** que la del servidor, caso por
// caso (`true` no es `1`, `0`/`false` no son "vacío", comparar tipos
// distintos da `false` en vez de fallar). Lo comprueba
// `test/core/forms/parity_test.dart` con los mismos casos que
// `server/visitacampo/forms/tests/test_parity.py`
// (`server/openapi/fixtures/forms_parity.json`).
import 'package:meta/meta.dart';

/// Clave de campo: `snake_case` ASCII, acotada (mismo patrón que el servidor).
final fieldKeyPattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

/// Profundidad máxima de anidamiento de una expresión.
const maxExprDepth = 6;

/// Operandos máximos de un `and`/`or`.
const maxOperands = 8;

/// Valores máximos en un `in`/`not_in`.
const maxMembershipValues = 64;

/// Operadores de comparación de orden (`gt`/`gte`/`lt`/`lte`).
const orderOperators = {'gt', 'gte', 'lt', 'lte'};

/// La plantilla no cumple el DSL. `path` señala dónde (`fields.3.visible_if.op`).
class InvalidDefinition implements Exception {
  const InvalidDefinition(this.path, this.reason);
  final String path;
  final String reason;

  @override
  String toString() => 'InvalidDefinition($path: $reason)';
}

@immutable
sealed class VisibilityExpr {
  const VisibilityExpr();
}

/// `campo <op> literal`, con `op` en `eq|ne|gt|gte|lt|lte`.
final class Comparison extends VisibilityExpr {
  const Comparison(this.op, this.field, this.value);
  final String op;
  final String field;

  /// `bool`, `num`, `String` o `null`: nunca una estructura.
  final Object? value;
}

/// `campo ∈ valores` / `campo ∉ valores`.
final class Membership extends VisibilityExpr {
  const Membership(this.op, this.field, this.values);
  final String op;
  final String field;
  final List<Object?> values;
}

/// `is_empty` / `is_not_empty`.
final class Presence extends VisibilityExpr {
  const Presence(this.op, this.field);
  final String op;
  final String field;
}

final class Not extends VisibilityExpr {
  const Not(this.operand);
  final VisibilityExpr operand;
}

/// `and` / `or`.
final class AndOr extends VisibilityExpr {
  const AndOr(this.op, this.operands);
  final String op;
  final List<VisibilityExpr> operands;
}

// --- Parseo estricto -------------------------------------------------------

bool _isScalar(Object? value) => value == null || value is bool || value is num || value is String;

void _onlyKeys(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw InvalidDefinition('$path.$key', 'extra_forbidden');
  }
}

String _fieldRef(Map<String, Object?> json, String path) {
  final field = json['field'];
  if (field is! String || !fieldKeyPattern.hasMatch(field)) {
    throw InvalidDefinition('$path.field', 'invalid_field_key');
  }
  return field;
}

/// Parsea una expresión (o lanza [InvalidDefinition]). La profundidad del JSON
/// ya está acotada por `checkJsonDepth` antes de llegar aquí, así que la
/// recursión no puede desbordar la pila.
VisibilityExpr parseVisibility(Object? raw, String path) {
  if (raw is! Map<String, Object?>) throw InvalidDefinition(path, 'not_an_object');
  final op = raw['op'];
  switch (op) {
    case 'eq' || 'ne' || 'gt' || 'gte' || 'lt' || 'lte':
      _onlyKeys(raw, const {'op', 'field', 'value'}, path);
      if (!raw.containsKey('value')) throw InvalidDefinition('$path.value', 'missing');
      final value = raw['value'];
      if (!_isScalar(value)) throw InvalidDefinition('$path.value', 'not_a_scalar');
      return Comparison(op! as String, _fieldRef(raw, path), value);
    case 'in' || 'not_in':
      _onlyKeys(raw, const {'op', 'field', 'value'}, path);
      final values = raw['value'];
      if (values is! List<Object?> || values.isEmpty || values.length > maxMembershipValues) {
        throw InvalidDefinition('$path.value', 'invalid_membership_list');
      }
      for (final (index, value) in values.indexed) {
        if (!_isScalar(value)) throw InvalidDefinition('$path.value.$index', 'not_a_scalar');
      }
      return Membership(op! as String, _fieldRef(raw, path), List.unmodifiable(values));
    case 'is_empty' || 'is_not_empty':
      _onlyKeys(raw, const {'op', 'field'}, path);
      return Presence(op! as String, _fieldRef(raw, path));
    case 'not':
      _onlyKeys(raw, const {'op', 'operand'}, path);
      return Not(parseVisibility(raw['operand'], '$path.operand'));
    case 'and' || 'or':
      _onlyKeys(raw, const {'op', 'operands'}, path);
      final operands = raw['operands'];
      if (operands is! List<Object?> || operands.length < 2 || operands.length > maxOperands) {
        throw InvalidDefinition('$path.operands', 'invalid_operand_count');
      }
      return AndOr(op! as String, [
        for (final (index, operand) in operands.indexed) parseVisibility(operand, '$path.operands.$index'),
      ]);
    default:
      // El caso de seguridad: `eval`, `system`, `call`, cualquier cosa.
      throw InvalidDefinition('$path.op', 'unknown_operator');
  }
}

// --- Inspección estructural ------------------------------------------------

int expressionDepth(VisibilityExpr expr) => switch (expr) {
  Not(:final operand) => 1 + expressionDepth(operand),
  AndOr(:final operands) => 1 + operands.map(expressionDepth).reduce((a, b) => a > b ? a : b),
  _ => 1,
};

/// Las hojas de la expresión (las que nombran un campo), en orden.
Iterable<VisibilityExpr> leaves(VisibilityExpr expr) sync* {
  switch (expr) {
    case Not(:final operand):
      yield* leaves(operand);
    case AndOr(:final operands):
      for (final operand in operands) {
        yield* leaves(operand);
      }
    default:
      yield expr;
  }
}

String leafField(VisibilityExpr leaf) => switch (leaf) {
  Comparison(:final field) || Membership(:final field) || Presence(:final field) => field,
  _ => throw StateError('no es una hoja'),
};

// --- Evaluación (pura, total, sin excepciones) -----------------------------

/// "Sin responder": `null`, cadena vacía, lista vacía u objeto vacío.
/// `false` y `0` **no** son vacíos.
bool isBlank(Object? value) =>
    value == null ||
    (value is String && value.isEmpty) ||
    (value is List && value.isEmpty) ||
    (value is Map && value.isEmpty);

bool _sameKind(Object? left, Object? right) {
  if (left is bool || right is bool) return left is bool && right is bool;
  if (left is num || right is num) return left is num && right is num;
  if (left == null || right == null) return left == null && right == null;
  return left.runtimeType == right.runtimeType ||
      (left is String && right is String) ||
      (left is List && right is List) ||
      (left is Map && right is Map);
}

bool _equals(Object? left, Object? right) => _sameKind(left, right) && left == right;

bool _ordered(String op, Object? left, Object? right) {
  if (!_sameKind(left, right) || left is bool || left == null) return false;
  final int comparison;
  if (left is num && right is num) {
    comparison = left.compareTo(right);
  } else if (left is String && right is String) {
    comparison = left.compareTo(right);
  } else {
    return false;
  }
  return switch (op) {
    'gt' => comparison > 0,
    'gte' => comparison >= 0,
    'lt' => comparison < 0,
    _ => comparison <= 0,
  };
}

/// ¿Es visible el campo cuya condición es [expr], dadas estas respuestas?
/// `null` (sin condición) es visible siempre.
bool evaluate(VisibilityExpr? expr, Map<String, Object?> answers) {
  switch (expr) {
    case null:
      return true;
    case AndOr(:final op, :final operands):
      return op == 'and'
          ? operands.every((operand) => evaluate(operand, answers))
          : operands.any((operand) => evaluate(operand, answers));
    case Not(:final operand):
      return !evaluate(operand, answers);
    case Presence(:final op, :final field):
      final blank = isBlank(answers[field]);
      return op == 'is_empty' ? blank : !blank;
    case Membership(:final op, :final field, :final values):
      final value = answers[field];
      final found = values.any((candidate) => _equals(value, candidate));
      return op == 'in' ? found : !found;
    case Comparison(:final op, :final field, :final value):
      final answer = answers[field];
      return switch (op) {
        'eq' => _equals(answer, value),
        'ne' => !_equals(answer, value),
        _ => _ordered(op, answer, value),
      };
  }
}
