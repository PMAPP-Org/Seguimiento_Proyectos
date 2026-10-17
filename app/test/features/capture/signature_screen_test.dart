// Pantalla de firma (Paso 22, tarea 4): el trazo se exporta como PNG real.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/features/capture/signature_screen.dart';
import 'package:visitacampo/ui/widgets/signature_pad.dart';

import '../../support/test_app.dart';

/// Abre la pantalla de firma desde una página anfitriona y devuelve lo que
/// esta recibe al cerrarse.
Future<List<Uint8List?>> pumpHost(WidgetTester tester) async {
  final results = <Uint8List?>[];
  await tester.pumpWidget(
    testApp(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              results.add(
                await Navigator.of(
                  context,
                ).push<Uint8List>(MaterialPageRoute(builder: (_) => const SignatureScreen(title: 'Firma del productor'))),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('firmar y aceptar devuelve un PNG', (tester) async {
    final results = await pumpHost(tester);
    expect(find.text('Firma del productor'), findsOneWidget);

    await tester.drag(find.byType(SignaturePad), const Offset(120, 30));
    await tester.pump();

    // La exportación a PNG usa el motor de verdad: fuera del reloj falso.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('signature_accept_button')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    final png = results.single!;
    expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], reason: 'firma PNG');
  });

  testWidgets('sin firmar no se acepta; borrar vacía el lienzo', (tester) async {
    final results = await pumpHost(tester);

    await tester.tap(find.byKey(const Key('signature_accept_button')));
    await tester.pump();
    expect(find.text('Firma antes de aceptar.'), findsOneWidget);
    expect(results, isEmpty);

    await tester.drag(find.byType(SignaturePad), const Offset(80, 10));
    await tester.tap(find.byKey(const Key('signature_clear_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('signature_accept_button')));
    await tester.pump();
    expect(results, isEmpty, reason: 'tras borrar vuelve a estar vacía');
  });

  test('el controlador sin trazos no exporta nada', () async {
    expect(await SignatureController().toPng(const Size(100, 50)), isNull);
  });
}
