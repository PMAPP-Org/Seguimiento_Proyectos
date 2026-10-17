// El sistema de diseño cumple lo que promete: objetivo táctil mínimo, colores
// de estado en ambos temas con contraste legible, y los widgets base se
// comportan igual que el código repetido que reemplazan.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/ui/theme/app_colors.dart';
import 'package:visitacampo/ui/theme/app_theme.dart';
import 'package:visitacampo/ui/theme/app_tokens.dart';
import 'package:visitacampo/ui/widgets/app_button.dart';
import 'package:visitacampo/ui/widgets/app_page_body.dart';

/// Relación de contraste WCAG 2.x entre dos colores opacos.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('AppTheme', () {
    for (final (name, theme, brightness) in [
      ('claro', AppTheme.light, Brightness.light),
      ('oscuro', AppTheme.dark, Brightness.dark),
    ]) {
      test('tema $name: Material 3, brillo correcto y colores de estado', () {
        expect(theme.useMaterial3, isTrue);
        expect(theme.colorScheme.brightness, brightness);
        expect(theme.extension<AppStatusColors>(), isNotNull);
      });

      test('tema $name: los colores de estado se leen (contraste ≥ 4.5:1, WCAG AA)', () {
        final status = theme.extension<AppStatusColors>()!;
        expect(_contrast(status.success, status.onSuccess), greaterThanOrEqualTo(4.5));
        expect(_contrast(status.warning, status.onWarning), greaterThanOrEqualTo(4.5));
      });

      test('tema $name: los botones nunca miden menos que el objetivo táctil', () {
        final size = theme.elevatedButtonTheme.style!.minimumSize!.resolve(<WidgetState>{})!;
        expect(size.height, AppSizes.minTouchTarget);
      });
    }

    test('AppStatusColors interpola entre temas sin perder campos', () {
      final mid = AppStatusColors.light.lerp(AppStatusColors.dark, 0.5);
      expect(mid.success, Color.lerp(AppStatusColors.light.success, AppStatusColors.dark.success, 0.5));
      expect(AppStatusColors.light.copyWith(), isA<AppStatusColors>());
      expect(AppStatusColors.light.lerp(null, 0.5), same(AppStatusColors.light));
    });
  });

  group('AppButton', () {
    Widget host(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

    testWidgets('normal: muestra la etiqueta y responde al toque', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(AppButton(label: 'Guardar', onPressed: () => taps++)));
      await tester.tap(find.text('Guardar'));
      expect(taps, 1);
      expect(tester.getSize(find.byType(ElevatedButton)).height, greaterThanOrEqualTo(AppSizes.minTouchTarget));
    });

    testWidgets('cargando: deshabilitado, con progreso y etiqueta accesible', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        host(
          AppButton(
            label: 'Guardar',
            loadingLabel: 'Guardando…',
            isLoading: true,
            onPressed: () => taps++,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Guardar'), findsNothing);
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
      expect(find.bySemanticsLabel('Guardando…'), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton));
      expect(taps, 0);
      handle.dispose();
    });
  });

  testWidgets('AppPageBody limita el ancho del contenido en pantallas anchas', (tester) async {
    tester.view.physicalSize = const Size(2000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPageBody(children: [Container(key: const Key('content'), height: 10)]),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const Key('content'))).width, AppSizes.maxContentWidth);
  });
}
