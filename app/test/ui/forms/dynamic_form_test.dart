// Renderer dinámico (Paso 21): cada tipo del catálogo se pinta, los campos
// condicionales aparecen y desaparecen al cambiar otras respuestas, y la
// validación de UX marca lo mismo que rechazaría el servidor.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/forms/form_definition.dart';
import 'package:visitacampo/ui/forms/dynamic_form.dart';
import 'package:visitacampo/ui/forms/form_controller.dart';

import '../../support/test_app.dart';

/// La plantilla `catalogo_completo` del fixture compartido con el servidor.
FormDefinition catalogo() {
  final fixture =
      jsonDecode(File('../server/openapi/fixtures/forms_parity.json').readAsStringSync()) as Map<String, dynamic>;
  final raw = (fixture['valid_definitions'] as List).cast<Map<String, dynamic>>().firstWhere(
    (t) => t['name'] == 'catalogo_completo',
  );
  return (parseFormDefinition(raw['definition']) as DefinitionOk).definition;
}

class FakeMedia implements FormMediaDelegate {
  final calls = <String>[];

  @override
  Future<String?> capturePhoto(String fieldKey) async {
    calls.add('photo:$fieldKey');
    return '0192f0e2-8a6b-7c3d-9e4f-5a6b7c8d9e0f';
  }

  @override
  Future<String?> captureSignature(String fieldKey) async {
    calls.add('signature:$fieldKey');
    return '0192f0e2-8a6b-7c3d-9e4f-5a6b7c8d9e10';
  }

  @override
  Future<Map<String, double>?> captureLocation(String fieldKey) async {
    calls.add('location:$fieldKey');
    return {'lat': 4.6, 'lon': -74.08};
  }
}

Future<void> pumpForm(WidgetTester tester, FormController controller, {FormMediaDelegate? media}) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(
      Scaffold(
        body: SingleChildScrollView(
          child: DynamicForm(controller: controller, mediaDelegate: media),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('cada tipo del catálogo se renderiza', (tester) async {
    final controller = FormController(
      catalogo(),
      initialAnswers: {'tiene_planta': true, 'altura_cm': 350, 'estado': 'plaga', 'conteo': 1},
    );
    await pumpForm(tester, controller, media: FakeMedia());

    expect(find.text('Inspección de cultivo'), findsOneWidget, reason: 'título en el idioma de la app');
    for (final label in [
      '¿Hay planta? *', // boolean
      'Altura (cm) *', // number
      'Estado sanitario', // single_choice
      '¿Qué plaga? *', // text
      'Conteo', // integer
      'Motivo de la altura', // text multilínea
      'Síntomas', // multi_choice
      'Fecha de siembra', // date
      'Revisado en', // datetime
      'Foto', // photo
      'Firma *', // signature
      'Ubicación', // location
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Con plaga'), findsOneWidget);
    expect(find.text('Raíz'), findsOneWidget);
  });

  testWidgets('los campos condicionales aparecen y desaparecen con las respuestas', (tester) async {
    final controller = FormController(catalogo());
    await pumpForm(tester, controller);

    expect(find.text('Altura (cm) *'), findsNothing);
    expect(find.text('¿Qué plaga? *'), findsNothing);
    expect(find.text('Síntomas'), findsNothing);

    // eq: tiene_planta == true muestra la altura y la firma.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sí'));
    await tester.pump();
    expect(find.text('Altura (cm) *'), findsOneWidget);
    expect(find.text('Firma *'), findsOneWidget);

    // in: estado ∈ [plaga] muestra la pregunta; not(is_empty) muestra síntomas.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Con plaga'));
    await tester.pump();
    expect(find.text('¿Qué plaga? *'), findsOneWidget);
    expect(find.text('Síntomas'), findsOneWidget);

    // and(gt, ne): la altura > 300 con estado distinto de "muerto".
    await tester.enterText(find.widgetWithText(TextField, 'Altura (cm) *'), '320');
    await tester.pump();
    expect(controller.valueOf('altura_cm'), 320);
    expect(find.text('Motivo de la altura'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Muerto'));
    await tester.pump();
    expect(find.text('Motivo de la altura'), findsNothing);
    expect(find.text('¿Qué plaga? *'), findsNothing);

    // Volver a "No" oculta la altura otra vez.
    await tester.tap(find.widgetWithText(ChoiceChip, 'No'));
    await tester.pump();
    expect(find.text('Altura (cm) *'), findsNothing);
    expect(controller.valueOf('tiene_planta'), false);
  });

  testWidgets('los errores aparecen al intentar guardar, no antes', (tester) async {
    final controller = FormController(catalogo(), initialAnswers: {'tiene_planta': true});
    await pumpForm(tester, controller);

    expect(find.text('Este campo es obligatorio.'), findsNothing);
    expect(controller.validate(), isFalse);
    await tester.pump();
    // altura_cm y firma: obligatorios y visibles.
    expect(find.text('Este campo es obligatorio.'), findsNWidgets(2));

    await tester.enterText(find.widgetWithText(TextField, 'Altura (cm) *'), 'mucho');
    await tester.pump();
    expect(find.text('Escribe un número.'), findsOneWidget);

    // Coma decimal (es-CO).
    await tester.enterText(find.widgetWithText(TextField, 'Altura (cm) *'), '12,5');
    await tester.pump();
    expect(controller.valueOf('altura_cm'), 12.5);
    expect(find.text('Escribe un número.'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Altura (cm) *'), '900');
    await tester.pump();
    expect(find.text('El valor está fuera del rango permitido.'), findsOneWidget);
  });

  testWidgets('selección múltiple: guarda en el orden de la plantilla y vacía quita la clave', (tester) async {
    final controller = FormController(catalogo(), initialAnswers: {'estado': 'sano'});
    await pumpForm(tester, controller);

    await tester.tap(find.widgetWithText(FilterChip, 'Raíz'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Hojas'));
    await tester.pump();
    expect(controller.valueOf('sintomas'), ['hojas', 'raiz']);

    await tester.tap(find.widgetWithText(FilterChip, 'Hojas'));
    await tester.tap(find.widgetWithText(FilterChip, 'Raíz'));
    await tester.pump();
    expect(controller.answers.containsKey('sintomas'), isFalse);
  });

  testWidgets('foto, firma y ubicación los captura la pantalla anfitriona', (tester) async {
    final media = FakeMedia();
    final controller = FormController(catalogo(), initialAnswers: {'tiene_planta': true});
    await pumpForm(tester, controller, media: media);

    await tester.tap(find.text('Tomar foto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Firmar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obtener ubicación'));
    await tester.pumpAndSettle();

    expect(media.calls, ['photo:foto', 'signature:firma', 'location:ubicacion']);
    expect(controller.valueOf('foto'), '0192f0e2-8a6b-7c3d-9e4f-5a6b7c8d9e0f');
    expect(controller.valueOf('ubicacion'), {'lat': 4.6, 'lon': -74.08});
    expect(find.text('Foto adjunta.'), findsOneWidget);
    expect(find.text('Repetir foto'), findsOneWidget);
    expect(find.text('lat: 4.6, lon: -74.08'), findsOneWidget);
  });

  testWidgets('sin captura disponible el botón queda deshabilitado', (tester) async {
    final controller = FormController(catalogo());
    await pumpForm(tester, controller);

    final button = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('No disponible en esta pantalla').first, matching: find.byType(OutlinedButton)),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('la plantilla es solo dato: un formulario completo y válido pasa la validación', (tester) async {
    final controller = FormController(
      catalogo(),
      initialAnswers: {
        'tiene_planta': true,
        'altura_cm': 100,
        'estado': 'sano',
        'firma': '0192f0e2-8a6b-7c3d-9e4f-5a6b7c8d9e10',
      },
    );
    await pumpForm(tester, controller);
    expect(controller.validate(), isTrue);
    await tester.pump();
    expect(find.text('Este campo es obligatorio.'), findsNothing);
  });

  test('datetime: offset local explícito; date: YYYY-MM-DD', () {
    expect(isoDate(DateTime(2026, 3, 2)), '2026-03-02');
    final value = isoDateTimeWithOffset(DateTime(2026, 3, 2, 9, 5));
    expect(value, startsWith('2026-03-02T09:05:00'));
    const field = DateTimeFieldDef(key: 'd', label: I18nText({'es': 'D'}), help: null, required: false, visibleIf: null);
    expect(field.checkAnswer(value), isNull, reason: 'el valor que produce el selector lo acepta el servidor');
  });
}
