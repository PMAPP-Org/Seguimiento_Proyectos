// Modelo de ejemplo del Paso 10: valida que el pipeline de codegen (freezed +
// json_serializable) funciona antes de construir el dominio real en el
// Paso 12. Espejo mínimo de `VisitData` (contrato `server/openapi/v1.yaml`,
// server/visitacampo/sync/schemas.py::VisitData) — solo los campos que
// bastan para probar el codegen, no el modelo completo del Paso 12.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'visit.freezed.dart';
part 'visit.g.dart';

@freezed
abstract class Visit with _$Visit {
  const factory Visit({
    required String id,
    required String orgId,
    required int version,
    required int changeSeq,
    DateTime? deletedAt,
    required String templateVersionId,
    required Map<String, dynamic> answers,
    double? lat,
    double? lon,
    double? accuracyM,
    double? altitudeM,
    required DateTime capturedAt,
    required String deviceId,
    required String createdBy,
  }) = _Visit;

  factory Visit.fromJson(Map<String, dynamic> json) => _$VisitFromJson(json);
}
