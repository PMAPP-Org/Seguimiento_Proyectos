import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Cuerpo estándar de una pantalla: margen de página, ancho máximo centrado en
/// tabletas y desplazamiento si el contenido no cabe (teclado abierto, texto
/// grande por accesibilidad).
class AppPageBody extends StatelessWidget {
  const AppPageBody({super.key, required this.children, this.centerVertically = false});

  final List<Widget> children;

  /// Centra el contenido en vertical (pantallas cortas como el login).
  final bool centerVertically;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AppSizes.maxContentWidth,
                minHeight: centerVertically
                    ? (constraints.maxHeight - 2 * AppSpacing.page).clamp(0, double.infinity)
                    : 0,
              ),
              child: Column(
                mainAxisAlignment: centerVertically
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Separación vertical entre elementos, siempre con un token de la escala.
class AppGap extends StatelessWidget {
  const AppGap(this.size, {super.key});

  /// Uno de los valores de `AppSpacing`.
  final double size;

  const AppGap.sm({super.key}) : size = AppSpacing.sm;
  const AppGap.lg({super.key}) : size = AppSpacing.lg;

  @override
  Widget build(BuildContext context) => SizedBox(height: size);
}
