// `LocationSource` — la mitad de GPS que `CaptureScreen` necesita (Tarea 6
// del plan de despliegue del demo). Interfaz + implementación real
// separadas, mismo patrón que `AuthTransport`/`SyncTransport`: los tests de
// `CaptureScreen` usan un fake, sin permisos de plataforma reales.
class LocationFix {
  const LocationFix({
    required this.lat,
    required this.lon,
    required this.accuracyM,
    this.altitudeM,
  });

  final double lat;
  final double lon;
  final double accuracyM;
  final double? altitudeM;
}

abstract class LocationSource {
  /// `null` si el usuario niega el permiso o el servicio de ubicación del
  /// sistema está apagado — `CaptureScreen` debe seguir permitiendo guardar
  /// la visita sin ubicación (`Visit.lat`/`lon` son opcionales en el
  /// contrato, `core/models/visit.py`).
  Future<LocationFix?> getCurrentFix();
}
