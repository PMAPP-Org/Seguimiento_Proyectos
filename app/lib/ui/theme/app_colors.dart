// Colores de VisitaCampo. ÚNICO archivo de `lib/` donde se escribe un color
// literal (`infra/scripts/lint_ui_tokens.sh`); el resto de la app los toma de
// `Theme.of(context).colorScheme` o de la extensión `AppStatusColors`.
import 'package:flutter/material.dart';

/// Color semilla de la marca: Material 3 deriva de él toda la paleta
/// (primario, contenedores, superficies) para tema claro y oscuro, con
/// contrastes ya calculados para texto (WCAG AA).
abstract final class AppPalette {
  static const Color brandSeed = Color(0xFF2E7D32);

  /// Firma: tinta y papel fijos, **no** del tema. La firma se exporta como
  /// PNG y se ve después en el back-office y en informes; con el tema oscuro
  /// saldría una firma clara sobre fondo oscuro, ilegible en papel.
  static const Color signatureInk = Color(0xFF111111);
  static const Color signaturePaper = Color(0xFFFFFFFF);
}

/// Colores de estado del dominio (sync, conflictos) que el `ColorScheme` de
/// Material no tiene. Se usan con `Theme.of(context).extension<AppStatusColors>()!`.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
  });

  /// Sincronizado / guardado.
  final Color success;
  final Color onSuccess;

  /// Pendiente de reintento / incompleto (no es un error: es trabajo en cola).
  final Color warning;
  final Color onWarning;

  static const light = AppStatusColors(
    success: Color(0xFF1B5E20),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFF8A5100),
    onWarning: Color(0xFFFFFFFF),
  );

  static const dark = AppStatusColors(
    success: Color(0xFF81C784),
    onSuccess: Color(0xFF003909),
    warning: Color(0xFFFFB74D),
    onWarning: Color(0xFF462A00),
  );

  @override
  AppStatusColors copyWith({Color? success, Color? onSuccess, Color? warning, Color? onWarning}) {
    return AppStatusColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
    );
  }
}
