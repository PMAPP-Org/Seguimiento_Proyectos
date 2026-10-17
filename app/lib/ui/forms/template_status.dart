// Qué decirle al agente cuando la plantilla no se puede usar (Paso 21).
import '../../data/local/form_template_repository.dart';
import '../../l10n/l10n.dart';

/// `null` si la plantilla está lista para renderizarse.
String? templateLookupMessage(AppLocalizations l10n, TemplateLookup lookup) => switch (lookup) {
  TemplateReady() => null,
  TemplateMissing() => l10n.formTemplateMissing,
  TemplateUnsupported() => l10n.formTemplateUnsupported,
  TemplateCorrupt() => l10n.formTemplateCorrupt,
};
