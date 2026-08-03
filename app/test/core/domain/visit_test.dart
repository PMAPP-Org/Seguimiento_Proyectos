// Humo del pipeline de codegen (freezed + json_serializable), Paso 10: si
// `build_runner` dejara de generar código correcto, este test es el primero
// en fallar, antes de que el dominio real del Paso 12 dependa de él.
import 'package:flutter_test/flutter_test.dart';
import 'package:visitacampo/core/domain/visit.dart';

void main() {
  group('Visit (freezed + json_serializable)', () {
    final capturedAt = DateTime.utc(2026, 7, 30, 14, 5, 9);

    Visit buildVisit({double? lat}) => Visit(
      id: 'a1a1a1a1-0000-0000-0000-000000000000',
      orgId: 'b2b2b2b2-0000-0000-0000-000000000000',
      version: 1,
      changeSeq: 42,
      templateVersionId: 'c3c3c3c3-0000-0000-0000-000000000000',
      answers: const {'altura_cm': 12},
      lat: lat,
      capturedAt: capturedAt,
      deviceId: 'd4d4d4d4-0000-0000-0000-000000000000',
      createdBy: 'e5e5e5e5-0000-0000-0000-000000000000',
    );

    test('copyWith produce una copia con el campo cambiado, no una mutación', () {
      final original = buildVisit(lat: 4.6);
      final moved = original.copyWith(lat: 4.7);

      expect(original.lat, 4.6, reason: 'copyWith no debe mutar el original');
      expect(moved.lat, 4.7);
    });

    test('== estructural: dos instancias con los mismos campos son iguales', () {
      expect(buildVisit(lat: 4.6), buildVisit(lat: 4.6));
    });

    test('toJson/fromJson hacen un roundtrip exacto', () {
      final visit = buildVisit(lat: 4.6);
      final roundtripped = Visit.fromJson(visit.toJson());

      expect(roundtripped, visit);
    });

    test('fromJson sin un campo requerido lanza, nunca produce un valor a medias', () {
      final incomplete = buildVisit(lat: 4.6).toJson()..remove('id');

      expect(() => Visit.fromJson(incomplete), throwsA(isA<TypeError>()));
    });

    test(
      'fromJson entiende snake_case real del contrato (app/build.yaml: '
      'field_rename: snake) — regresión: un roundtrip contra sí mismo no '
      'detecta un desajuste consistente en ambas direcciones',
      () {
        final visit = Visit.fromJson({
          'id': 'a1a1a1a1-0000-0000-0000-000000000000',
          'org_id': 'b2b2b2b2-0000-0000-0000-000000000000',
          'version': 1,
          'change_seq': 42,
          'deleted_at': null,
          'template_version_id': 'c3c3c3c3-0000-0000-0000-000000000000',
          'answers': {'altura_cm': 12},
          'lat': 4.6,
          'lon': null,
          'accuracy_m': null,
          'altitude_m': null,
          'captured_at': capturedAt.toIso8601String(),
          'device_id': 'd4d4d4d4-0000-0000-0000-000000000000',
          'created_by': 'e5e5e5e5-0000-0000-0000-000000000000',
        });

        expect(visit.orgId, 'b2b2b2b2-0000-0000-0000-000000000000');
        expect(visit.changeSeq, 42);
        expect(visit.templateVersionId, 'c3c3c3c3-0000-0000-0000-000000000000');
        expect(visit.toJson(), containsPair('org_id', 'b2b2b2b2-0000-0000-0000-000000000000'));
      },
    );
  });
}
