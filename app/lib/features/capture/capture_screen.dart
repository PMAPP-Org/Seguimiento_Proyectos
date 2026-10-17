// Captura de visita (Paso 22): plantilla → formulario dinámico (Paso 21) →
// ubicación, fotos y firma → guardado offline en una sola transacción.
//
// - La plantilla sale de la caché local (`FormTemplateRepository`), la versión
//   vigente para una visita **nueva**; sin plantillas, se pide sincronizar.
// - Foto, firma y ubicación de los campos de la plantilla se capturan aquí
//   (`FormMediaDelegate`) y el formulario guarda solo el `id` del adjunto.
// - Aparte del formulario: la ubicación de la visita (`Visit.lat/lon`, con su
//   precisión) y fotos adicionales.
// - Guardar es local e inmediato (`VisitCapture.save`): la visita aparece en
//   la pantalla de inicio sin esperar a la red.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_state.dart';
import '../../core/capture/visit_capture.dart';
import '../../core/location/location_source.dart';
import '../../core/providers.dart';
import '../../data/local/form_template_repository.dart';
import '../../l10n/l10n.dart';
import '../../ui/forms/dynamic_form.dart';
import '../../ui/forms/form_controller.dart';
import '../../ui/forms/template_status.dart';
import '../../ui/widgets/app_button.dart';
import '../../ui/widgets/app_page_body.dart';
import 'signature_screen.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> implements FormMediaDelegate {
  List<TemplateVersionInfo>? _templates;
  String? _templateId;
  TemplateLookup? _lookup;
  FormController? _form;

  LocationFix? _fix;
  bool _locating = false;
  bool _saving = false;

  /// Adjuntos de los campos foto/firma, por `id` (lo que guarda `answers`).
  final Map<String, PendingAttachment> _captured = {};
  final List<PendingAttachment> _extraPhotos = [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _form?.dispose();
    super.dispose();
  }

  String? get _orgId => switch (ref.read(appDependenciesProvider).authController.state) {
    Authenticated(:final user) => user.orgId,
    _ => null,
  };

  Future<void> _loadTemplates() async {
    final orgId = _orgId;
    if (orgId == null) return;
    final templates = await ref.read(appDependenciesProvider).formTemplates.availableTemplates(orgId: orgId);
    if (!mounted) return;
    setState(() => _templates = templates);
    if (templates.length == 1) await _selectTemplate(templates.single.templateId);
  }

  Future<void> _selectTemplate(String? templateId) async {
    final orgId = _orgId;
    if (templateId == null || orgId == null) return;
    final lookup = await ref
        .read(appDependenciesProvider)
        .formTemplates
        .latestForNewVisit(orgId: orgId, templateId: templateId);
    if (!mounted) return;
    setState(() {
      _templateId = templateId;
      _lookup = lookup;
      _form?.dispose();
      _form = lookup is TemplateReady ? FormController(lookup.definition) : null;
      _captured.clear();
    });
  }

  // --- FormMediaDelegate -----------------------------------------------------

  @override
  Future<String?> capturePhoto(String fieldKey) async {
    final photo = await _takePhoto();
    if (photo == null) return null;
    _captured[photo.id] = photo;
    return photo.id;
  }

  @override
  Future<String?> captureSignature(String fieldKey) async {
    final dependencies = ref.read(appDependenciesProvider);
    final field = _form?.definition.fields.where((f) => f.key == fieldKey).firstOrNull;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final png = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => SignatureScreen(title: field?.label.resolve(locale) ?? context.l10n.signatureTitle),
      ),
    );
    if (png == null) return null;
    final stored = await dependencies.signatureStore.save(png);
    final signature = PendingAttachment(
      id: dependencies.visitCapture.newAttachmentId(),
      sha256: stored.sha256,
      localPath: stored.path,
      mime: 'image/png',
      role: 'firma',
      capturedAt: DateTime.now(),
    );
    _captured[signature.id] = signature;
    return signature.id;
  }

  @override
  Future<Map<String, double>?> captureLocation(String fieldKey) async {
    final fix = await ref.read(appDependenciesProvider).locationSource.getCurrentFix();
    return fix == null ? null : {'lat': fix.lat, 'lon': fix.lon};
  }

  // ---------------------------------------------------------------------------

  Future<PendingAttachment?> _takePhoto() async {
    final dependencies = ref.read(appDependenciesProvider);
    final photo = await dependencies.photoCapture.takePhoto();
    if (photo == null) return null;
    return PendingAttachment(
      id: dependencies.visitCapture.newAttachmentId(),
      sha256: photo.sha256,
      localPath: photo.file.path,
      mime: photo.mime,
      role: 'foto',
      capturedAt: DateTime.now(),
    );
  }

  Future<void> _addExtraPhoto() async {
    final photo = await _takePhoto();
    if (photo == null || !mounted) return;
    setState(() => _extraPhotos.add(photo));
  }

  Future<void> _getLocation() async {
    setState(() => _locating = true);
    final fix = await ref.read(appDependenciesProvider).locationSource.getCurrentFix();
    if (!mounted) return;
    setState(() {
      _fix = fix;
      _locating = false;
    });
    if (fix == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.captureLocationUnavailable)));
    }
  }

  Future<void> _save() async {
    final dependencies = ref.read(appDependenciesProvider);
    final authState = dependencies.authController.state;
    final form = _form;
    final lookup = _lookup;
    if (authState is! Authenticated || form == null || lookup is! TemplateReady) return;

    final l10n = context.l10n;
    if (!form.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.captureFixErrors)));
      return;
    }

    setState(() => _saving = true);
    try {
      await dependencies.visitCapture.save(
        identity: CaptureIdentity(
          orgId: authState.user.orgId,
          userId: authState.user.id,
          deviceId: dependencies.deviceId,
        ),
        templateVersionId: lookup.info.id,
        definition: lookup.definition,
        answers: form.answers,
        captured: Map.of(_captured),
        extraPhotos: List.of(_extraPhotos),
        fix: _fix,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.captureSaved)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final templates = _templates;
    final lookup = _lookup;
    final form = _form;
    final fix = _fix;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.captureTitle)),
      body: AppPageBody(
        children: [
          if (templates == null)
            const Center(child: CircularProgressIndicator())
          else if (templates.isEmpty)
            Text(l10n.captureNoTemplates, key: const Key('capture_no_templates'))
          else ...[
            if (templates.length > 1)
              DropdownButtonFormField<String>(
                key: const Key('capture_template_picker'),
                initialValue: _templateId,
                decoration: InputDecoration(labelText: l10n.captureTemplateLabel),
                items: [
                  for (final t in templates) DropdownMenuItem(value: t.templateId, child: Text(t.name ?? t.templateId)),
                ],
                onChanged: _selectTemplate,
              ),
            if (lookup != null && templateLookupMessage(l10n, lookup) != null) ...[
              const AppGap.sm(),
              Text(templateLookupMessage(l10n, lookup)!, key: const Key('capture_template_problem')),
            ],
            if (form != null) ...[
              const AppGap.lg(),
              DynamicForm(controller: form, mediaDelegate: this),
              const AppGap.sm(),
              Text(l10n.captureVisitLocation, style: Theme.of(context).textTheme.titleSmall),
              if (fix != null) Text(l10n.captureLocationWithAccuracy('${fix.lat}', '${fix.lon}', fix.accuracyM.round())),
              AppButton(
                key: const Key('capture_get_location_button'),
                label: fix == null ? l10n.captureGetLocation : l10n.formUpdateLocation,
                isLoading: _locating,
                onPressed: _getLocation,
              ),
              const AppGap.lg(),
              Text(l10n.captureExtraPhotos(_extraPhotos.length), style: Theme.of(context).textTheme.titleSmall),
              OutlinedButton(
                key: const Key('capture_add_photo_button'),
                onPressed: _addExtraPhoto,
                child: Text(l10n.captureAddPhoto),
              ),
              const AppGap.lg(),
              AppButton(
                key: const Key('capture_save_button'),
                label: l10n.captureSave,
                loadingLabel: l10n.captureSaving,
                isLoading: _saving,
                onPressed: _save,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
