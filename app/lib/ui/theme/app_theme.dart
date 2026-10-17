// Tema de VisitaCampo (Material 3, claro y oscuro). Todo el aspecto de los
// componentes se decide aquí: las pantallas no pasan estilos sueltos.
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light, AppStatusColors.light);

  static ThemeData get dark => _build(Brightness.dark, AppStatusColors.dark);

  static ThemeData _build(Brightness brightness, AppStatusColors status) {
    final scheme = ColorScheme.fromSeed(seedColor: AppPalette.brandSeed, brightness: brightness);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [status],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      // Botones a todo el ancho disponible y nunca por debajo del objetivo
      // táctil mínimo.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.minTouchTarget),
          shape: shape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.minTouchTarget),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.minTouchTarget),
          shape: shape,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

/// Acceso corto a los colores de estado: `context.statusColors.warning`.
extension AppThemeContext on BuildContext {
  AppStatusColors get statusColors => Theme.of(this).extension<AppStatusColors>()!;
}
