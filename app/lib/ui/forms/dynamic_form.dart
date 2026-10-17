// Renderer dinámico de formularios (Paso 21, tarea 2).
//
// **El catálogo de widgets es cerrado y vive en el binario** (ADR-012): el
// `switch` de [_FieldInput] sobre la clase sellada `FormFieldDef` es
// exhaustivo, así que un tipo de campo nuevo no compila hasta tener su widget,
// y la plantilla no puede describir comportamiento: solo elige un tipo de la
// lista y lo parametriza con datos (etiquetas, rangos, opciones).
//
// La captura de foto, firma y ubicación la hace la pantalla anfitriona a
// través de [FormMediaDelegate] (Paso 22): el renderer solo guarda en
// `answers` el identificador que devuelve, nunca el binario.
import 'package:flutter/material.dart';

import '../../core/forms/form_definition.dart';
import '../../l10n/l10n.dart';
import '../theme/app_tokens.dart';
import 'form_controller.dart';

/// Captura de los campos que necesitan hardware. Devuelve `null` si el
/// usuario cancela.
abstract interface class FormMediaDelegate {
  /// Id (UUID) del `visit_attachment` de la foto.
  Future<String?> capturePhoto(String fieldKey);

  /// Id (UUID) del `visit_attachment` de la firma.
  Future<String?> captureSignature(String fieldKey);

  /// `{"lat": …, "lon": …}`.
  Future<Map<String, double>?> captureLocation(String fieldKey);
}

class DynamicForm extends StatelessWidget {
  const DynamicForm({super.key, required this.controller, this.mediaDelegate});

  final FormController controller;
  final FormMediaDelegate? mediaDelegate;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final title = controller.definition.title;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title.resolve(locale), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
            ],
            for (final field in controller.visibleFields)
              Padding(
                // La clave mantiene el estado (texto escrito) de cada campo
                // aunque otros aparezcan o desaparezcan alrededor.
                key: ValueKey('form-field-${field.key}'),
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _FieldInput(
                  field: field,
                  locale: locale,
                  controller: controller,
                  mediaDelegate: mediaDelegate,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Mensaje para un `reason` de validación (los mismos del servidor).
String formErrorMessage(AppLocalizations l10n, String reason) => switch (reason) {
  'required' => l10n.formErrorRequired,
  'too_short' => l10n.formErrorTooShort,
  'too_long' => l10n.formErrorTooLong,
  'not_a_number' || 'not_finite' => l10n.formErrorNotANumber,
  'not_an_integer' => l10n.formErrorNotAnInteger,
  'out_of_range' => l10n.formErrorOutOfRange,
  'too_few_selected' => l10n.formErrorTooFewSelected,
  'too_many_selected' => l10n.formErrorTooManySelected,
  _ => l10n.formErrorInvalid,
};

class _FieldInput extends StatelessWidget {
  const _FieldInput({
    required this.field,
    required this.locale,
    required this.controller,
    required this.mediaDelegate,
  });

  final FormFieldDef field;
  final String locale;
  final FormController controller;
  final FormMediaDelegate? mediaDelegate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = field.label.resolve(locale);
    final shownLabel = field.required ? l10n.formFieldRequired(label) : label;
    final help = field.help?.resolve(locale);
    final reason = controller.errorFor(field.key);
    final error = reason == null ? null : formErrorMessage(l10n, reason);
    final value = controller.valueOf(field.key);
    void set(Object? newValue) => controller.setAnswer(field.key, newValue);

    // Exhaustivo sobre la clase sellada: el catálogo cerrado (ADR-012).
    return switch (field) {
      TextFieldDef(:final multiline, :final maxLength) => _TextAnswer(
        label: shownLabel,
        help: help,
        error: error,
        initial: value is String ? value : '',
        multiline: multiline,
        maxLength: maxLength,
        keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
        parse: (text) => text,
        onChanged: set,
      ),
      NumberFieldDef() => _TextAnswer(
        label: shownLabel,
        help: help,
        error: error,
        initial: value?.toString() ?? '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        // Coma decimal (es-CO) o punto. Lo que no es un número se guarda tal
        // cual, para que la validación diga "no es un número" en vez de
        // perder lo escrito en silencio.
        parse: (text) => text.isEmpty ? null : (num.tryParse(text.trim().replaceAll(',', '.')) ?? text),
        onChanged: set,
      ),
      IntegerFieldDef() => _TextAnswer(
        label: shownLabel,
        help: help,
        error: error,
        initial: value?.toString() ?? '',
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        parse: (text) => text.isEmpty ? null : (int.tryParse(text.trim()) ?? text),
        onChanged: set,
      ),
      BooleanFieldDef() => _Labeled(
        label: shownLabel,
        help: help,
        error: error,
        child: Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final (option, text) in [(true, l10n.formYes), (false, l10n.formNo)])
              ChoiceChip(
                label: Text(text),
                selected: value == option,
                onSelected: (selected) => set(selected ? option : null),
              ),
          ],
        ),
      ),
      DateFieldDef() => _Labeled(
        label: shownLabel,
        help: help,
        error: error,
        child: OutlinedButton(
          onPressed: () async {
            final current = value is String && isValidIsoDate(value) ? DateTime.parse(value) : DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: current,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (picked != null) set(isoDate(picked));
          },
          child: Text(
            value is String && isValidIsoDate(value)
                ? MaterialLocalizations.of(context).formatMediumDate(DateTime.parse(value))
                : l10n.formPickDate,
          ),
        ),
      ),
      DateTimeFieldDef() => _Labeled(
        label: shownLabel,
        help: help,
        error: error,
        child: OutlinedButton(
          onPressed: () async {
            final now = DateTime.now();
            final day = await showDatePicker(
              context: context,
              initialDate: now,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (day == null || !context.mounted) return;
            final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
            if (time == null) return;
            set(isoDateTimeWithOffset(DateTime(day.year, day.month, day.day, time.hour, time.minute)));
          },
          child: Text(value is String ? value : l10n.formPickDateTime),
        ),
      ),
      SingleChoiceFieldDef(:final options) => _Labeled(
        label: shownLabel,
        help: help,
        error: error,
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option.label.resolve(locale)),
                selected: value == option.value,
                onSelected: (selected) => set(selected ? option.value : null),
              ),
          ],
        ),
      ),
      MultiChoiceFieldDef(:final options) => _Labeled(
        label: shownLabel,
        help: help,
        error: error,
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final option in options)
              FilterChip(
                label: Text(option.label.resolve(locale)),
                selected: value is List && value.contains(option.value),
                onSelected: (selected) {
                  // El valor de **ahora**, no el del último build: dos toques
                  // seguidos antes de redibujar no pueden pisarse.
                  final now = controller.valueOf(field.key);
                  final current = [if (now is List) ...now.whereType<String>()];
                  selected ? current.add(option.value) : current.remove(option.value);
                  // Orden de la plantilla, no el de los toques.
                  set([
                    for (final o in options)
                      if (current.contains(o.value)) o.value,
                  ]);
                },
              ),
          ],
        ),
      ),
      PhotoFieldDef() => _CaptureAnswer(
        label: shownLabel,
        help: help,
        error: error,
        status: value == null ? null : l10n.formPhotoAttached,
        actionLabel: value == null ? l10n.formTakePhoto : l10n.formRetakePhoto,
        capture: mediaDelegate == null ? null : () => mediaDelegate!.capturePhoto(field.key),
        onCaptured: set,
      ),
      SignatureFieldDef() => _CaptureAnswer(
        label: shownLabel,
        help: help,
        error: error,
        status: value == null ? null : l10n.formSignatureAttached,
        actionLabel: value == null ? l10n.formSign : l10n.formResign,
        capture: mediaDelegate == null ? null : () => mediaDelegate!.captureSignature(field.key),
        onCaptured: set,
      ),
      LocationFieldDef() => _CaptureAnswer(
        label: shownLabel,
        help: help,
        error: error,
        status: value is Map ? l10n.captureLocation('${value['lat']}', '${value['lon']}') : null,
        actionLabel: value == null ? l10n.formGetLocation : l10n.formUpdateLocation,
        capture: mediaDelegate == null ? null : () => mediaDelegate!.captureLocation(field.key),
        onCaptured: set,
      ),
    };
  }
}

/// `YYYY-MM-DD` (el formato del tipo `date`).
String isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// RFC 3339 con el offset local explícito (el tipo `datetime` lo exige).
String isoDateTimeWithOffset(DateTime local) {
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.inHours.abs().toString().padLeft(2, '0');
  final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  return '${isoDate(local)}T$time$sign$hours:$minutes';
}

/// Etiqueta, ayuda y error alrededor de un control que no es un `TextField`.
class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.help, required this.error, required this.child});

  final String label;
  final String? help;
  final String? error;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        if (help != null) Text(help!, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xs),
        child,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}

class _TextAnswer extends StatefulWidget {
  const _TextAnswer({
    required this.label,
    required this.help,
    required this.error,
    required this.initial,
    required this.keyboardType,
    required this.parse,
    required this.onChanged,
    this.multiline = false,
    this.maxLength,
  });

  final String label;
  final String? help;
  final String? error;
  final String initial;
  final TextInputType keyboardType;
  final Object? Function(String text) parse;
  final ValueChanged<Object?> onChanged;
  final bool multiline;
  final int? maxLength;

  @override
  State<_TextAnswer> createState() => _TextAnswerState();
}

class _TextAnswerState extends State<_TextAnswer> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      keyboardType: widget.keyboardType,
      minLines: widget.multiline ? 3 : 1,
      maxLines: widget.multiline ? null : 1,
      maxLength: widget.maxLength,
      decoration: InputDecoration(labelText: widget.label, helperText: widget.help, errorText: widget.error),
      onChanged: (text) => widget.onChanged(widget.parse(text)),
    );
  }
}

class _CaptureAnswer extends StatefulWidget {
  const _CaptureAnswer({
    required this.label,
    required this.help,
    required this.error,
    required this.status,
    required this.actionLabel,
    required this.capture,
    required this.onCaptured,
  });

  final String label;
  final String? help;
  final String? error;

  /// Qué hay capturado (`null`: nada todavía).
  final String? status;
  final String actionLabel;

  /// `null`: la pantalla anfitriona no ofrece esta captura.
  final Future<Object?> Function()? capture;
  final ValueChanged<Object?> onCaptured;

  @override
  State<_CaptureAnswer> createState() => _CaptureAnswerState();
}

class _CaptureAnswerState extends State<_CaptureAnswer> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final result = await widget.capture!();
      if (result != null) widget.onCaptured(result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Labeled(
      label: widget.label,
      help: widget.help,
      error: widget.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.status != null) Text(widget.status!),
          OutlinedButton(
            onPressed: widget.capture == null || _busy ? null : _run,
            child: Text(widget.capture == null ? l10n.formCaptureUnavailable : widget.actionLabel),
          ),
        ],
      ),
    );
  }
}
