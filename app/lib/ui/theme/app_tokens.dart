// Tokens de diseño de VisitaCampo: la única fuente de medidas de la UI.
//
// Las pantallas (`lib/features/`) no escriben números de espaciado, radios
// ni tamaños: usan estos tokens. Lo comprueba `infra/scripts/lint_ui_tokens.sh`
// en CI, igual que el lint RD-01 para TLS. Cambiar el ritmo visual de toda la
// app es cambiar un valor aquí.

/// Escala de espaciado (múltiplos de 4 dp, la rejilla de Material 3).
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Margen interior de una página.
  static const double page = lg;
}

/// Radios de esquina.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
}

/// Tamaños fijos de componentes.
abstract final class AppSizes {
  /// Objetivo táctil mínimo (Material / WCAG 2.5.8): se trabaja en campo,
  /// a veces con guantes o el teléfono en una mano.
  static const double minTouchTarget = 48;

  /// Indicador de progreso dentro de un botón.
  static const double buttonProgress = 20;
  static const double buttonProgressStroke = 2;

  /// Ancho máximo del contenido en tabletas: un formulario de 1200 dp de
  /// ancho se lee peor que uno centrado.
  static const double maxContentWidth = 560;

  /// Lienzo de firma: alto en pantalla y grosor del trazo.
  static const double signatureHeight = 240;
  static const double signatureStroke = 3;
}
