// Paridad cliente ↔ servidor del DSL de formularios (Paso 21): los mismos
// casos que `server/visitacampo/forms/tests/test_parity.py`, leídos del mismo
// archivo (`server/openapi/fixtures/forms_parity.json`).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/forms/answers.dart';
import 'package:visitacampo/core/forms/form_definition.dart';

Map<String, dynamic> _fixture() {
  final file = File('../server/openapi/fixtures/forms_parity.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

FormDefinition _valid(Object? raw) => switch (parseFormDefinition(raw)) {
  DefinitionOk(:final definition) => definition,
  DefinitionInvalid(:final path, :final reason) => fail('plantilla válida rechazada: $path $reason'),
};

void main() {
  final fixture = _fixture();
  final validDefinitions = (fixture['valid_definitions'] as List).cast<Map<String, dynamic>>();
  final invalidDefinitions = (fixture['invalid_definitions'] as List).cast<Map<String, dynamic>>();

  group('plantillas válidas: visibilidad y violaciones iguales al servidor', () {
    for (final template in validDefinitions) {
      final definition = _valid(template['definition']);
      for (final rawCase in (template['cases'] as List).cast<Map<String, dynamic>>()) {
        test('${template['name']} / ${rawCase['name']}', () {
          final answers = (rawCase['answers'] as Map).cast<String, Object?>();
          expect(visibleFields(definition, answers).map((f) => f.key).toList(), rawCase['visible']);
          expect(
            validateAnswers(definition, answers).map((v) => [v.fieldKey, v.reason]).toList(),
            rawCase['violations'],
          );
        });
      }
    }
  });

  group('plantillas inválidas: se rechazan sin evaluarse (H-06)', () {
    for (final template in invalidDefinitions) {
      test('${template['name']}', () {
        expect(parseFormDefinition(template['definition']), isA<DefinitionInvalid>());
      });
    }
  });

  group('solo en el cliente', () {
    test('un dialecto futuro se distingue de una plantilla corrupta', () {
      final result = parseFormDefinition({'dsl': 'visitacampo/form@2', 'fields': <Object?>[]});
      expect(result, isA<DefinitionInvalid>().having((r) => r.unsupportedDialect, 'unsupportedDialect', isTrue));

      final corrupt = parseFormDefinition({'fields': 'no-es-una-lista'});
      expect(corrupt, isA<DefinitionInvalid>().having((r) => r.unsupportedDialect, 'unsupportedDialect', isFalse));
    });

    test('cualquier JSON arbitrario produce un resultado, nunca una excepción', () {
      for (final raw in <Object?>[
        null,
        42,
        'texto',
        <Object?>[],
        <String, Object?>{},
        {'fields': null},
        {
          'fields': [null, 1, 'x', <Object?>[]],
        },
        {
          'fields': [
            {'key': 'a', 'type': 'text', 'label': 'no-es-un-mapa'},
          ],
        },
        {
          'fields': [
            {'key': 'a', 'type': 'number', 'label': {'es': 'A'}, 'min': 'cero'},
          ],
        },
      ]) {
        expect(() => parseFormDefinition(raw), returnsNormally, reason: '$raw');
        expect(parseFormDefinition(raw), isA<DefinitionInvalid>(), reason: '$raw');
      }
    });

    test('un JSON anidado miles de niveles se rechaza sin agotar la pila', () {
      Object? nested = true;
      for (var i = 0; i < 5000; i++) {
        nested = {'op': 'not', 'operand': nested};
      }
      final raw = {
        'fields': [
          {'key': 'a', 'type': 'boolean', 'label': {'es': 'A'}},
          {'key': 'b', 'type': 'text', 'label': {'es': 'B'}, 'visible_if': nested},
        ],
      };
      expect(
        parseFormDefinition(raw),
        isA<DefinitionInvalid>().having((r) => r.reason, 'reason', 'too_deep'),
      );
    });

    test('sin coerción de tipos: "true" no es true, 3.0 no es un entero', () {
      expect(
        parseFormDefinition({
          'fields': [
            {'key': 'a', 'type': 'text', 'label': {'es': 'A'}, 'required': 'true'},
          ],
        }),
        isA<DefinitionInvalid>(),
      );
      expect(
        parseFormDefinition({
          'fields': [
            {'key': 'a', 'type': 'integer', 'label': {'es': 'A'}, 'min': 3.0},
          ],
        }),
        isA<DefinitionInvalid>(),
      );
    });

    test('etiquetas: idioma exacto, luego el idioma base, luego la primera declarada', () {
      const label = I18nText({'en': 'Height', 'es': 'Altura', 'es-CO': 'Altura (Colombia)'});
      expect(label.resolve('es-CO'), 'Altura (Colombia)');
      expect(label.resolve('es-MX'), 'Altura');
      expect(label.resolve('fr'), 'Height');
    });

    test('fechas: el 30 de febrero no existe y un datetime sin offset no vale', () {
      expect(isValidIsoDate('2026-02-28'), isTrue);
      expect(isValidIsoDate('2026-02-30'), isFalse);
      expect(isValidIsoDate('2026-2-3'), isFalse);
      const field = DateTimeFieldDef(key: 'd', label: I18nText({'es': 'D'}), help: null, required: false, visibleIf: null);
      expect(field.checkAnswer('2026-03-02T10:00:00Z'), isNull);
      expect(field.checkAnswer('2026-03-02T10:00:00-05:00'), isNull);
      expect(field.checkAnswer('2026-03-02T10:00:00'), 'naive_datetime');
      expect(field.checkAnswer('2026-03-02'), 'naive_datetime');
      expect(field.checkAnswer('ayer'), 'not_a_datetime');
    });
  });
}
