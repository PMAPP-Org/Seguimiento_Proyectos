import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Botón de acción con estado de carga.
///
/// Mientras `isLoading` es `true` se deshabilita y muestra un indicador de
/// progreso, y el lector de pantalla anuncia `loadingLabel` en vez de quedarse
/// sin etiqueta. Reemplaza el `ElevatedButton` + `SizedBox` +
/// `CircularProgressIndicator` que cada pantalla repetía a mano.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.loadingLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Texto para lectores de pantalla mientras carga (por defecto, `label`).
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? Semantics(
              label: loadingLabel ?? label,
              child: const SizedBox.square(
                dimension: AppSizes.buttonProgress,
                child: CircularProgressIndicator(strokeWidth: AppSizes.buttonProgressStroke),
              ),
            )
          : Text(label),
    );
  }
}
