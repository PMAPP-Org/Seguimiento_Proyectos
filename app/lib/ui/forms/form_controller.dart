// Estado de un formulario dinámico en pantalla (Paso 21).
//
// Guarda las respuestas, recalcula la visibilidad en cada cambio (el DSL es un
// recorrido lineal acotado: barato) y valida con las mismas reglas que el
// servidor — **solo para UX** (ADR-012): el servidor revalida en el push.
import 'package:flutter/foundation.dart';

import '../../core/forms/answers.dart';
import '../../core/forms/form_definition.dart';
import '../../core/forms/visibility.dart';

class FormController extends ChangeNotifier {
  FormController(this.definition, {Map<String, Object?> initialAnswers = const {}})
    : _answers = Map.of(initialAnswers);

  final FormDefinition definition;
  final Map<String, Object?> _answers;

  /// Los errores se muestran tras el primer intento de guardar, no mientras
  /// el agente todavía está escribiendo.
  bool _showErrors = false;
  bool get showErrors => _showErrors;

  /// Respuestas actuales (sin claves en blanco), en el formato de `answers`.
  Map<String, Object?> get answers => Map.unmodifiable(_answers);

  Object? valueOf(String key) => _answers[key];

  List<FormFieldDef> get visibleFields => [
    for (final field in definition.fields)
      if (evaluate(field.visibleIf, _answers)) field,
  ];

  List<AnswerViolation> get violations => validateAnswers(definition, _answers);

  /// El `reason` del primer error de [key], si hay que mostrarlo.
  String? errorFor(String key) {
    if (!_showErrors) return null;
    for (final violation in violations) {
      if (violation.fieldKey == key) return violation.reason;
    }
    return null;
  }

  /// Fija la respuesta de [key]. Un valor en blanco **quita** la clave: así
  /// `answers` no lleva `""` ni `[]` que el servidor tendría que interpretar.
  void setAnswer(String key, Object? value) {
    if (isBlank(value)) {
      if (_answers.remove(key) == null) return;
    } else {
      _answers[key] = value;
    }
    notifyListeners();
  }

  /// Intento de guardar: muestra los errores y devuelve si no hay ninguno.
  bool validate() {
    _showErrors = true;
    notifyListeners();
    return violations.isEmpty;
  }
}
