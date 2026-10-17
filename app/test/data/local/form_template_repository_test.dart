// Caché de plantillas (Paso 21, tareas 5-6), incluida la regresión de H-11:
// una versión nueva de la plantilla deja de servir la anterior para visitas
// nuevas, sin que las visitas históricas pierdan la suya.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/forms/form_definition.dart';
import 'package:visitacampo/data/local/database.dart';
import 'package:visitacampo/data/local/form_template_repository.dart';

const org = '00000000-0000-4000-8000-0000000000aa';
const template = '00000000-0000-4000-8000-0000000000bb';
const v1 = '00000000-0000-4000-8000-000000000001';
const v2 = '00000000-0000-4000-8000-000000000002';

Map<String, dynamic> definitionWith(String fieldKey) => {
  'dsl': 'visitacampo/form@1',
  'fields': [
    {
      'key': fieldKey,
      'type': 'text',
      'label': {'es': fieldKey},
    },
  ],
};

Map<String, dynamic> serverRow({
  required String id,
  required int versionNumber,
  Map<String, dynamic>? definition,
  String? publishedAt = '2026-10-01T00:00:00Z',
  String orgId = org,
  String templateId = template,
}) => {
  'id': id,
  'org_id': orgId,
  'version': 1,
  'change_seq': 10 + versionNumber,
  'deleted_at': null,
  'template_id': templateId,
  'name': 'Inspección',
  'version_number': versionNumber,
  'definition': definition ?? definitionWith('campo_v$versionNumber'),
  'published_at': publishedAt,
};

String firstFieldKey(TemplateLookup lookup) => switch (lookup) {
  TemplateReady(:final definition) => definition.fields.first.key,
  _ => fail('se esperaba una plantilla lista, llegó $lookup'),
};

void main() {
  late AppDatabase db;
  late FormTemplateRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FormTemplateRepository(db);
  });
  tearDown(() => db.close());

  test('H-11: al llegar la v2, una visita nueva usa la v2; la histórica sigue leyendo la v1', () async {
    await repo.upsertFromServerRow(serverRow(id: v1, versionNumber: 1));
    // La v1 entra en la caché de parseo.
    expect(firstFieldKey(await repo.latestForNewVisit(orgId: org, templateId: template)), 'campo_v1');
    expect(repo.cachedEntries, 1);

    await repo.upsertFromServerRow(serverRow(id: v2, versionNumber: 2));
    expect(repo.cachedEntries, 0, reason: 'la llegada de la v2 invalida explícitamente la plantilla');

    expect(
      firstFieldKey(await repo.latestForNewVisit(orgId: org, templateId: template)),
      'campo_v2',
      reason: 'una visita nueva nunca recibe la versión anterior',
    );
    expect(
      firstFieldKey(await repo.forVisit(orgId: org, templateVersionId: v1)),
      'campo_v1',
      reason: 'una visita que ya referencia la v1 sigue pudiendo interpretarse',
    );
  });

  test('la caché se indexa por organización: el mismo id en otra org no se mezcla', () async {
    await repo.upsertFromServerRow(serverRow(id: v1, versionNumber: 1));
    expect(await repo.forVisit(orgId: 'otra-org', templateVersionId: v1), isA<TemplateMissing>());
    expect(await repo.latestForNewVisit(orgId: 'otra-org', templateId: template), isA<TemplateMissing>());
  });

  test('un borrador sin publicar no se ofrece para visitas nuevas', () async {
    await repo.upsertFromServerRow(serverRow(id: v1, versionNumber: 1));
    await repo.upsertFromServerRow(serverRow(id: v2, versionNumber: 2, publishedAt: null));
    expect(firstFieldKey(await repo.latestForNewVisit(orgId: org, templateId: template)), 'campo_v1');
  });

  test('tombstone: la versión retirada no se ofrece, pero la visita histórica la lee', () async {
    await repo.upsertFromServerRow(serverRow(id: v1, versionNumber: 1));
    await repo.upsertFromServerRow(serverRow(id: v2, versionNumber: 2));
    await repo.markDeleted(v2, DateTime.utc(2026, 10, 2));

    expect(firstFieldKey(await repo.latestForNewVisit(orgId: org, templateId: template)), 'campo_v1');
    expect(firstFieldKey(await repo.forVisit(orgId: org, templateVersionId: v2)), 'campo_v2');
  });

  test('definición corrupta en disco: no se interpreta, se borra y se pide un pull completo', () async {
    await db.writeCursor('c1:00000000000000000042', now: DateTime.utc(2026));
    await repo.upsertFromServerRow(serverRow(id: v1, versionNumber: 1));
    // Alguien (un bug, el disco) estropea la fila guardada.
    await (db.update(db.formTemplateVersions)..where((t) => t.id.equals(v1))).write(
      FormTemplateVersionsCompanion(definitionJson: Value(jsonEncode({'fields': 'roto'}))),
    );
    repo = FormTemplateRepository(db); // sin la caché de parseo de antes

    expect(await repo.forVisit(orgId: org, templateVersionId: v1), isA<TemplateCorrupt>());
    expect(await db.select(db.formTemplateVersions).get(), isEmpty);
    expect(await db.readCursor(), isNull, reason: 'el siguiente pull vuelve a traerla del servidor');
  });

  test('dialecto futuro: "actualiza la app", sin borrar ni re-sincronizar', () async {
    await db.writeCursor('c1:00000000000000000042', now: DateTime.utc(2026));
    await repo.upsertFromServerRow(
      serverRow(id: v1, versionNumber: 1, definition: {'dsl': 'visitacampo/form@2', 'fields': <Object?>[]}),
    );
    expect(await repo.latestForNewVisit(orgId: org, templateId: template), isA<TemplateUnsupported>());
    expect(await db.select(db.formTemplateVersions).get(), hasLength(1));
    expect(await db.readCursor(), 'c1:00000000000000000042');
  });

  test('una fila que no cumple el contrato se ignora sin lanzar', () async {
    for (final broken in <Map<String, dynamic>>[
      {...serverRow(id: v1, versionNumber: 1), 'version_number': '1'},
      {...serverRow(id: v1, versionNumber: 1), 'definition': 'no-es-un-objeto'},
      {...serverRow(id: v1, versionNumber: 1), 'published_at': 'ayer'},
      {...serverRow(id: v1, versionNumber: 1)}..remove('org_id'),
    ]) {
      expect(await repo.upsertFromServerRow(broken), isFalse);
    }
    expect(await db.select(db.formTemplateVersions).get(), isEmpty);
  });

  test('plantillas disponibles: la vigente de cada una', () async {
    const other = '00000000-0000-4000-8000-0000000000cc';
    await repo.upsertFromServerRow(serverRow(id: v1, versionNumber: 1));
    await repo.upsertFromServerRow(serverRow(id: v2, versionNumber: 2));
    await repo.upsertFromServerRow(serverRow(id: '00000000-0000-4000-8000-000000000003', versionNumber: 1, templateId: other));

    final available = await repo.availableTemplates(orgId: org);
    expect(available.map((t) => (t.templateId, t.versionNumber)), containsAll([(template, 2), (other, 1)]));
    expect(available, hasLength(2));
  });

  test('la plantilla guardada se parsea con el meta-schema completo', () async {
    await repo.upsertFromServerRow(serverRow(id: v1, versionNumber: 1));
    final lookup = await repo.forVisit(orgId: org, templateVersionId: v1);
    expect(lookup, isA<TemplateReady>().having((t) => t.definition.fields.first, 'campo', isA<TextFieldDef>()));
  });
}
