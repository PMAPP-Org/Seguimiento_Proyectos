// Caché de plantillas de formulario (Paso 21, tareas 5-6).
//
// Las plantillas llegan por el pull (`SyncEngine`) como filas
// `form_template_version` y se guardan en `form_template_versions`. Este
// repositorio responde a dos preguntas distintas, y no mezclarlas es la
// corrección de H-11:
//
// - **¿Con qué plantilla se captura una visita nueva?** → [latestForNewVisit]:
//   la versión publicada más alta, no borrada, de esa plantilla. Se consulta
//   en la BD cada vez; lo único que se memoriza es el resultado del parseo de
//   cada versión.
// - **¿Con qué plantilla se lee una visita existente?** → [forVisit]: la
//   versión exacta que la visita referencia, aunque haya otra más nueva o esta
//   se haya retirado.
//
// La memoria de parseo se indexa por `(org_id, template_version_id)` y se
// invalida **explícitamente** al recibir cualquier fila de la plantilla
// ([upsertFromServerRow], [markDeleted]). Las versiones son inmutables, así que
// la invalidación casi nunca cambia nada; está para que la corrección no
// dependa de esa promesa.
//
// Una definición que no supera la validación estructural se trata como **dato
// corrupto**: no se interpreta, se borra la fila y se pide un pull completo
// (`resetCursor`). Una definición de un dialecto que este binario no conoce
// (`@2`) no es corrupción: la app necesita actualizarse, y re-sincronizar no
// lo arreglaría.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../core/forms/form_definition.dart';
import 'database.dart';

@immutable
class TemplateVersionInfo {
  const TemplateVersionInfo({
    required this.id,
    required this.orgId,
    required this.templateId,
    required this.versionNumber,
    required this.name,
  });

  final String id;
  final String orgId;
  final String templateId;
  final int versionNumber;
  final String? name;
}

/// Resultado de buscar una plantilla: nunca una excepción.
@immutable
sealed class TemplateLookup {
  const TemplateLookup();
}

final class TemplateReady extends TemplateLookup {
  const TemplateReady(this.info, this.definition);
  final TemplateVersionInfo info;
  final FormDefinition definition;
}

/// No hay ninguna versión utilizable (no ha llegado por el pull, o se retiró).
final class TemplateMissing extends TemplateLookup {
  const TemplateMissing();
}

/// La plantilla habla un dialecto que este binario no conoce: hay que
/// actualizar la app.
final class TemplateUnsupported extends TemplateLookup {
  const TemplateUnsupported(this.info);
  final TemplateVersionInfo info;
}

/// La definición guardada no es válida. Ya se borró y se pidió re-sincronizar.
final class TemplateCorrupt extends TemplateLookup {
  const TemplateCorrupt(this.path, this.reason);
  final String path;
  final String reason;
}

class FormTemplateRepository {
  FormTemplateRepository(this.db);

  final AppDatabase db;

  /// Resultado del parseo por `(org_id, template_version_id)`, junto con el
  /// `template_id` de esa versión (para invalidar la plantilla entera).
  final Map<(String, String), (String, DefinitionResult)> _parsed = {};

  @visibleForTesting
  int get cachedEntries => _parsed.length;

  /// Guarda una fila `form_template_version` del pull. `false` si la fila no
  /// tiene la forma del contrato: se ignora (no se interpreta a medias) y no
  /// bloquea el resto del pull.
  Future<bool> upsertFromServerRow(Map<String, dynamic> data) async {
    final row = _rowFromServer(data);
    if (row == null) return false;
    await db.into(db.formTemplateVersions).insertOnConflictUpdate(row);
    _invalidateTemplate(row.orgId.value, row.templateId.value, versionId: row.id.value);
    return true;
  }

  /// Tombstone del pull: la versión deja de ofrecerse para visitas nuevas.
  Future<void> markDeleted(String versionId, DateTime deletedAt) async {
    final row = await (db.select(db.formTemplateVersions)..where((t) => t.id.equals(versionId))).getSingleOrNull();
    if (row == null) return;
    await (db.update(db.formTemplateVersions)..where((t) => t.id.equals(versionId))).write(
      FormTemplateVersionsCompanion(deletedAt: Value(deletedAt)),
    );
    _invalidateTemplate(row.orgId, row.templateId, versionId: versionId);
  }

  /// La versión con la que se captura una visita **nueva** de [templateId].
  Future<TemplateLookup> latestForNewVisit({required String orgId, required String templateId}) async {
    final row =
        await (db.select(db.formTemplateVersions)
              ..where(
                (t) =>
                    t.orgId.equals(orgId) &
                    t.templateId.equals(templateId) &
                    t.publishedAt.isNotNull() &
                    t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.versionNumber)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? const TemplateMissing() : _lookup(row);
  }

  /// La versión exacta que referencia una visita existente, retirada o no.
  Future<TemplateLookup> forVisit({required String orgId, required String templateVersionId}) async {
    final row =
        await (db.select(db.formTemplateVersions)
              ..where((t) => t.orgId.equals(orgId) & t.id.equals(templateVersionId)))
            .getSingleOrNull();
    return row == null ? const TemplateMissing() : _lookup(row);
  }

  /// Plantillas disponibles para una visita nueva: la versión vigente de cada
  /// una, ordenadas por nombre.
  Future<List<TemplateVersionInfo>> availableTemplates({required String orgId}) async {
    final rows =
        await (db.select(db.formTemplateVersions)
              ..where((t) => t.orgId.equals(orgId) & t.publishedAt.isNotNull() & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.versionNumber)]))
            .get();
    final latest = <String, FormTemplateVersion>{};
    for (final row in rows) {
      latest.putIfAbsent(row.templateId, () => row);
    }
    final infos = latest.values.map(_info).toList()
      ..sort((a, b) => (a.name ?? a.templateId).compareTo(b.name ?? b.templateId));
    return infos;
  }

  Future<TemplateLookup> _lookup(FormTemplateVersion row) async {
    final info = _info(row);
    final (_, result) = _parsed.putIfAbsent(
      (row.orgId, row.id),
      () => (row.templateId, _parse(row.definitionJson)),
    );
    switch (result) {
      case DefinitionOk(:final definition):
        return TemplateReady(info, definition);
      case DefinitionInvalid(unsupportedDialect: true):
        return TemplateUnsupported(info);
      case DefinitionInvalid(:final path, :final reason):
        // Corrupta: fuera de la caché y de la BD, y pull completo para
        // recuperarla del servidor (que la validó al publicarla).
        _parsed.remove((row.orgId, row.id));
        await db.transaction(() async {
          await (db.delete(db.formTemplateVersions)..where((t) => t.id.equals(row.id))).go();
          await db.resetCursor();
        });
        return TemplateCorrupt(path, reason);
    }
  }

  /// Fuera de la caché la versión recibida y **todas** las de su plantilla:
  /// barato, y la corrección no depende de que una versión publicada no
  /// cambie nunca.
  void _invalidateTemplate(String orgId, String templateId, {required String versionId}) {
    _parsed.remove((orgId, versionId));
    _parsed.removeWhere((key, value) => key.$1 == orgId && value.$1 == templateId);
  }

  static DefinitionResult _parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const DefinitionInvalid('definition', 'not_json');
    }
    return parseFormDefinition(decoded);
  }

  static TemplateVersionInfo _info(FormTemplateVersion row) {
    return TemplateVersionInfo(
      id: row.id,
      orgId: row.orgId,
      templateId: row.templateId,
      versionNumber: row.versionNumber,
      name: row.name,
    );
  }

  /// Contrato `FormTemplateVersion` → fila local, o `null` si no cumple.
  static FormTemplateVersionsCompanion? _rowFromServer(Map<String, dynamic> data) {
    final id = data['id'];
    final orgId = data['org_id'];
    final templateId = data['template_id'];
    final versionNumber = data['version_number'];
    final version = data['version'];
    final changeSeq = data['change_seq'];
    final name = data['name'];
    final definition = data['definition'];
    if (id is! String ||
        orgId is! String ||
        templateId is! String ||
        versionNumber is! int ||
        version is! int ||
        (changeSeq != null && changeSeq is! int) ||
        (name != null && name is! String) ||
        definition is! Map<String, dynamic>) {
      return null;
    }
    final (publishedOk, publishedAt) = _date(data['published_at']);
    final (deletedOk, deletedAt) = _date(data['deleted_at']);
    if (!publishedOk || !deletedOk) return null;
    return FormTemplateVersionsCompanion.insert(
      id: id,
      orgId: orgId,
      templateId: templateId,
      versionNumber: versionNumber,
      name: Value(name as String?),
      definitionJson: jsonEncode(definition),
      publishedAt: Value(publishedAt),
      deletedAt: Value(deletedAt),
      version: version,
      changeSeq: Value(changeSeq as int?),
    );
  }

  /// Fecha opcional del contrato: `(true, null)` si viene `null`; `(false, _)`
  /// si no es una fecha.
  static (bool, DateTime?) _date(Object? value) {
    if (value == null) return (true, null);
    final parsed = value is String ? DateTime.tryParse(value) : null;
    return (parsed != null, parsed);
  }
}
